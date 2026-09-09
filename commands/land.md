---
description: Turn the current checkpoint into real, reviewed commits on this branch
allowed-tools: Bash(git:*), Bash(sh:*), AskUserQuestion, Read
---

!`sh "${CLAUDE_PLUGIN_ROOT}/commands/land-context.sh"`

L'utilisateur a demande : $ARGUMENTS

C'est le moment ou du travail en cours devient de l'historique. C'est le seul
endroit du plugin ou quelque chose entre dans la branche du projet, et rien n'y
entre sans que l'utilisateur ait valide le message.

## Marche a suivre

1. **S'il n'y a aucun checkpoint**, dis-le en une ligne et arrete-toi. S'il y en
   a un mais que sa base ne correspond pas au HEAD local, ne tente rien
   d'automatique : explique la divergence et propose `git diff HEAD refs/git-sync/current`.

2. **Si le work tree local est deja sale**, c'est le cas normal quand tu landes
   depuis la machine qui vient de travailler : le contenu du checkpoint est
   deja la. Travaille sur le work tree. Sinon, applique d'abord le checkpoint
   avec `git read-tree -u -m HEAD refs/git-sync/current && git reset`.

3. **Lis le diff** (`git diff HEAD refs/git-sync/current`) et decide s'il porte
   un seul sujet ou plusieurs. Plusieurs repertoires sans rapport, ou des
   prefixes conventionnels differents (`feat` / `fix` / `docs` / `chore`), sont
   le signal qu'il faut decouper.

   - Un seul sujet : propose **un** commit, sans ceremonie.
   - Plusieurs : propose un decoupage, en donnant pour chaque commit son
     message et les fichiers concernes, et dans un ordre ou chaque commit se
     tient tout seul. Sors les changements sans rapport en premier, pour que la
     paire feature + doc reste contigue.

4. **Signale ce qui ne devrait pas etre committe** : `print`/`console.log` de
   debug, `TODO` laisse en place, fichier temporaire, secret. Demande avant de
   retirer quoi que ce soit.

5. **Fais valider** le decoupage et les messages avant de committer. L'utilisateur
   peut ajuster.

6. **Committe** par chemins (`git add <fichiers>` puis `git commit`), pousse la
   branche, puis supprime le checkpoint devenu inutile :
   `git push origin --delete git-sync/<branche>`. Ne supprime pas
   `.git/git-sync-pushed` en entier : il porte l'etat de toutes les branches.
   Les hooks nettoient d'eux-memes la ligne devenue obsolete au demarrage
   suivant, donc il n'y a rien a faire de plus ici.

7. **Si le checkpoint venait d'une autre machine** -- c'est-a-dire si `Origine`
   differe de `Cette machine` -- dis a l'utilisateur d'y faire un `git pull`.
   Elle detient encore ce travail non committe et ignore qu'il vient
   d'atterrir. Sa prochaine session le lui signalerait de toute facon, mais un
   `git pull` evite la confusion. **Quand les deux sont identiques, ne dis
   rien** : envoyer quelqu'un vers la machine sur laquelle il se trouve deja
   fait douter de tout le reste.

## Regles

- Les messages suivent la convention deja visible dans `git log` du depot. Va la
  lire plutot que d'imposer la tienne.
- Ne decoupe jamais a l'interieur d'un fichier (`git add -p`). Si deux sujets se
  croisent dans le meme fichier, fais un seul commit et dis pourquoi.
- Ne committe jamais sans que l'utilisateur ait vu les messages.
- Ne supprime le checkpoint qu'apres un push reussi.
- Termine par une ligne : ce qui a ete committe, et le checkpoint supprime.
