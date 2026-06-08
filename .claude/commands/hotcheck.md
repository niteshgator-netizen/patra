A hot file is about to be edited. Before any edit:
1. Read the FULL current version of the file (every line, not a snippet).
2. Count and report: total lines, number of def, number of end, number of if/case/do blocks.
3. Confirm all def/if/case/do have matching end.
4. State which hot file this is and confirm no other hot file will be touched in the same change.
5. Only then propose the edit. Wrap Telegram calls in safe_telegram, external API calls in begin/rescue StandardError.
