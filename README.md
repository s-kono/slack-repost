> **Warning** no warranty, thread is not supported

1. set TOKEN
2. $ ./slack-repost.sh <target_channel> [<post_channel>] 

```sh
[diff]
--- slack-repost.sh
+++ slack-repost_del-repostimglink.sh
@@ -52,7 +52,7 @@
     filestat="${DIR_WORK}/${old_ts}.filestat"
     echo -n "ok" > "${filestat}"

-    text="$( jq -r .text < <( echo "${jsonline}" ) )"
+    text="$( jq -r .text < <( echo "${jsonline}" ) | perl -pe 's,(?: +<https://[^\.]+\.slack\.com/files/[^ \|]+\| >)*$,,' )"
     files="$( jq .files < <( echo "${jsonline}" ) )"
     if [ "${files}" = null ]; then
         fileurls=
```
