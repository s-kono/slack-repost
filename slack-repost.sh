#!/bin/bash

# no warranty

TOKEN=""

export LANG=C
export LC_CTYPE=en_US.utf8
export PATH=/sbin:/bin:/usr/sbin:/usr/bin

target_ch="$1"
post_ch="$2"
set -u
[ -z "${post_ch}" ] && post_ch="${target_ch}"

FULL0="$( readlink -f "${BASH_SOURCE:-$0}" )"
DIR=$( dirname "${FULL0}" )
NAME=$( basename "${FULL0}" .sh )

DIR_WORK="${DIR}/.tmp"
[ -d "${DIR_WORK}" ] || mkdir "${DIR_WORK}"

PASTDAY=88
THRESHOLD=$( date +%s -d"${PASTDAY} days ago" )

# https://api.slack.com/methods/conversations.history
curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
  --get \
  -H "Authorization: Bearer ${TOKEN:?}" \
  -H 'Content-Type:application/x-www-form-urlencoded' \
  https://slack.com/api/conversations.history \
  -d "limit=1000" \
  -d "channel=${target_ch}" \
  -o "${DIR_WORK}/history"

if [ "$( jq .ok "${DIR_WORK}/history" )" != true ]; then
    echo >&2 "[error] conversations.history ${target_ch}"
    exit 2
fi
if [ "$( jq .has_more "${DIR_WORK}/history" )" != false ]; then
    echo >&2 "[warning] history:has_more ${target_ch}"
fi

while read -r jsonline; do

    sleep 10

    old_ts="$( jq -r .ts < <( echo "${jsonline}" ) )"

    [ "$( echo "${old_ts}" | awk -F. '{print $1}' )" -lt "${THRESHOLD}" ] \
    || continue

    text="$( jq -r .text < <( echo "${jsonline}" ) )"
    files="$( jq .files < <( echo "${jsonline}" ) )"
    if [ "${files}" = null ]; then
        fileurls=
    else
        fileurls="$(
          while read -r url_private_download; do

              sleep 1
              filename=$( echo "${url_private_download}" | awk -F/ '{print $NF}' )

              if ! curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
                --get \
                -H "Authorization: Bearer ${TOKEN:?}" \
                -H 'Content-Type:application/x-www-form-urlencoded' \
                "${url_private_download}" -o "${DIR_WORK}/${filename}" ; then
                  echo >&2 "[error] file:download ${url_private_download} => ${DIR_WORK}/${filename} (skip_the_rest:${old_ts}@${target_ch})"
                  jq . < <( echo "${jsonline}" ) >&2
                  continue 2
              fi

              sleep 1

              # https://api.slack.com/methods/files.upload
              curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
                -X POST \
                -H "Authorization: Bearer ${TOKEN:?}" \
                -F file=@"${DIR_WORK}/${filename}" \
                https://slack.com/api/files.upload \
                -o "${DIR_WORK}/${old_ts}.upload"

              if [ "$( jq .ok "${DIR_WORK}/${old_ts}.upload" )" != true ]; then
                  echo >&2 "[error] files.upload[reupload] ${DIR_WORK}/${filename} (skip_the_rest:${old_ts}@${target_ch})"
                  jq . < <( echo "${jsonline}" ) >&2
                  jq . "${DIR_WORK}/${old_ts}.upload" >&2
                  continue 2
              fi

              rm "${DIR_WORK}/${filename}"

              reupload=$( jq -r .file.permalink "${DIR_WORK}/${old_ts}.upload" )
              echo "${reupload}" | sed -e 's/^/ </' -e 's/$/| >/'

          done < <( jq -r '.[].url_private_download' < <( echo "${files}" ) ) \
          | tr -d '\n'
        )"
    fi

    sleep 1

    # https://api.slack.com/methods/chat.postMessage
    curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
      -X POST \
      -H 'Content-Type:application/x-www-form-urlencoded' \
      -H "Authorization: Bearer ${TOKEN:?}" \
      https://slack.com/api/chat.postMessage \
      -d "channel=${post_ch}" \
      -d "unfurl_links=true" \
      -d "unfurl_media=true" \
      --data-urlencode "text=${text} ${fileurls}" \
      -o "${DIR_WORK}/${old_ts}.repost"

    if [ "$( jq .ok "${DIR_WORK}/${old_ts}.repost" )" != true ]; then
        echo >&2 "[error] chat.postMessage[repost] (skip_the_rest:${old_ts}@${target_ch}=>${post_ch})"
        jq . < <( echo "${jsonline}" ) >&2
        jq . "${DIR_WORK}/${old_ts}.repost" >&2
        continue
    fi

    new_ts=$( jq -r .ts "${DIR_WORK}/${old_ts}.repost" )

    sleep 1

    # https://api.slack.com/methods/chat.delete
    curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
      -X POST \
      -H "Authorization: Bearer ${TOKEN:?}" \
      -H 'Content-Type:application/x-www-form-urlencoded' \
      https://slack.com/api/chat.delete \
      -d "channel=${target_ch}" \
      -d "ts=${old_ts}" \
      -o "${DIR_WORK}/${old_ts}.del"

    if [ "$( jq .ok "${DIR_WORK}/${old_ts}.del" )" != true ]; then
        echo >&2 "[error] chat.delete (skip_the_rest:${old_ts}@${target_ch})"
        jq . < <( echo "${jsonline}" ) >&2
        jq . "${DIR_WORK}/${old_ts}.del" >&2
        continue
    fi

    if [ "$( jq '.is_starred' < <( echo "${jsonline}" ) )" = true ]; then
        sleep 1

        # https://api.slack.com/methods/stars.add
        curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
          -X POST \
          -H "Authorization: Bearer ${TOKEN:?}" \
          -H 'Content-Type:application/x-www-form-urlencoded' \
          https://slack.com/api/stars.add \
          -d "channel=${post_ch}" \
          -d "timestamp=${new_ts}" \
          -o "${DIR_WORK}/${old_ts}.new.star"

        if [ "$( jq .ok "${DIR_WORK}/${old_ts}.new.star" )" != true ]; then
            echo >&2 "[error] stars.add (skip_the_rest:${old_ts}@${target_ch}=>${new_ts}@${post_ch})"
            jq . < <( echo "${jsonline}" ) >&2
            jq . "${DIR_WORK}/${old_ts}.new.star" >&2
            continue
        fi
    fi
    if [ "$( jq '.pinned_to' < <( echo "${jsonline}" ) )" != null ]; then
        sleep 1

        # https://api.slack.com/methods/pins.add
        curl --compressed -sS --retry 1 --retry-delay 15 -m 7 \
          -X POST \
          -H "Authorization: Bearer ${TOKEN:?}" \
          -H 'Content-Type:application/x-www-form-urlencoded' \
          https://slack.com/api/pins.add \
          -d "channel=${post_ch}" \
          -d "timestamp=${new_ts}" \
          -o "${DIR_WORK}/${old_ts}.new.pin"

        if [ "$( jq .ok "${DIR_WORK}/${old_ts}.new.pin" )" != true ]; then
            echo >&2 "[error] pins.add (skip_the_rest:${old_ts}@${target_ch}=>${new_ts}@${post_ch})"
            jq . < <( echo "${jsonline}" ) >&2
            jq . "${DIR_WORK}/${old_ts}.new.pin" >&2
            continue
        fi
    fi

done < <( jq -c '.messages[]' "${DIR_WORK}/history" | tac )

rm -f "${DIR_WORK}"/*

exit
