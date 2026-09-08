---
description: Turn the current checkpoint into real, reviewed commits on this branch
allowed-tools: Bash(git:*), AskUserQuestion, Read
---

Branche courante : !`git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(HEAD detache)"`
Checkpoint : !`git fetch -q origin "+refs/heads/git-sync/$(git symbolic-ref --quiet --short HEAD)":refs/git-sync/current 2>/dev/null; git rev-parse -q --verify refs/git-sync/current 2>/dev/null || echo "(aucun)"`
Origine : !`git log -1 --format=%B refs/git-sync/current 2>/dev/null | sed -n 's/^Git-Sync-Machine:[[:space:]]*//p'`
Base du checkpoint : !`git log -1 --format=%B refs/git-sync/current 2>/dev/null | sed -n 's/^Git-Sync-Base:[[:space:]]*//p'`
HEAD local : !`git rev-parse HEAD`
Resume : !`git diff --stat HEAD refs/git-sync/current 2>/dev/null | tail -30`

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
   `git push origin --delete git-sync/<branche>` et
   `rm -f .git/git-sync-pushed`.

## Regles

- Les messages suivent la convention deja visible dans `git log` du depot. Va la
  lire plutot que d'imposer la tienne.
- Ne decoupe jamais a l'interieur d'un fichier (`git add -p`). Si deux sujets se
  croisent dans le meme fichier, fais un seul commit et dis pourquoi.
- Ne committe jamais sans que l'utilisateur ait vu les messages.
- Ne supprime le checkpoint qu'apres un push reussi.
- Termine par une ligne : ce qui a ete committe, et le checkpoint supprime.
