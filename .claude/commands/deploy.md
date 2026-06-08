Print the exact Patra deploy sequence for Genius to run. Do NOT run it yourself. Output this:

PowerShell deploy steps:
1. git add <the specific files changed>
2. git add public/vite/
3. git commit --no-verify -m "MESSAGE"
4. git push clean main --force
5. git push origin main

If origin rejects (non-fast-forward, happens often):
  git fetch origin
  git rebase origin/main
  git checkout --theirs public/vite/
  git add public/vite/
  git rebase --continue   (opens Vim: press Esc, type :wq, press Enter)
  git push origin main

Then: trigger Manual Deploy on Render for BOTH Web Service + Background Worker. Both must go green.
