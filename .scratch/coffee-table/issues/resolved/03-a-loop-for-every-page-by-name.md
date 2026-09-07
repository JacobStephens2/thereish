# 03: A loop for every Page, by name

**What to build:** An evening of five Pages is not one tune five times. When a Page is written the Room picks a house loop at random among the loops other than the one this Room played last, holds the choice in its process state (a restart may repeat once; that is fine), and puts it on the snapshot as the Page's loop, name and path, so every view resolves the same file. A **"Now playing"** line appears below the fold on the Stage and on the Speaker's phone: the loop's name and the words "the house loop", or "Music is off" under Off. `foley:page` carries the loop's title and a kind beside the path. Spec sections: Loop rotation; Pushed events.

**Blocked by:** 01 (The forge, again: seven new sounds), 02 (The music control and the levels).

**Status:** resolved

- [x] Writing a Page picks a loop from the loop-names module, never the loop the Room played on its previous Page; the snapshot carries the Page's loop as name and path
- [x] `foley:page` under `house`, or under `page` before a Track lands, carries the loop's path, its name as `title`, and `kind: "house"`
- [x] A "Now playing" line renders below the fold on the Stage and on the Speaker's phone — never on a phone that is not the Speaker — naming the loop and calling it the house loop, or saying music is off
- [x] Room tests for the no-immediate-repeat rule across three Pages and for the snapshot's loop; LiveView tests for the line's text and for the push's title and kind
