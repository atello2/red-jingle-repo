#!/bin/bash

shopt -s nullglob

if ! command -v 3dstool >/dev/null 2>&1
then
    echo "3dstool could not be found. Please install 3dstool to your PATH."
    exit 1
fi
if ! command -v vgmstream-cli >/dev/null 2>&1
then
    echo "vgmstream-cli could not be found. Please install vgmstream-cli to your PATH."
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1
then
    echo "python3 could not be found. This is not required, but may cause problems, so we exit here anyways.."
    exit 1
fi

mkdir -p jingles/n3ds

for ROM in *.3ds *.cci; do
    echo "Processing $ROM..."
    OUTPUT="${ROM%.*}.wav"

    3dstool -xvtf cci "$ROM" -0 partition0.cxi --header /dev/null > /dev/null
    3dstool -xvtf cxi partition0.cxi --exefs exefs.bin --exefs-auto-key > /dev/null
    3dstool -xvtfu exefs exefs.bin --exefs-dir exefs_dir/ > /dev/null

    mv exefs_dir/banner.bnr banner.bin

    3dstool -xvtf banner banner.bin --banner-dir banner_dir/ > /dev/null

    # Trim bcwav to the size declared in its header
    python3 -c "
import struct
with open('banner_dir/banner.bcwav','rb') as f:
    data = f.read()
size = struct.unpack('<I', data[12:16])[0]
with open('banner_dir/banner.bcwav','wb') as f:
    f.write(data[:size])
"

    vgmstream-cli banner_dir/banner.bcwav -o "jingles/n3ds/$OUTPUT" > /dev/null

    rm -r partition0.cxi exefs.bin exefs_dir/ banner.bin banner_dir/

    FINAL=$(printf '%s\n' "$OUTPUT" \
        | iconv -f utf-8 -t ascii//TRANSLIT \
        | awk '
    {
        s=$0

        # 1. Strip TitleID prefix
        sub(/^0004[0-9A-Fa-f]{12}[-_ ]?/, "", s)

        # 2. Protect extension
        if (match(s, /\.[^.]+$/)) {
            ext=substr(s,RSTART); s=substr(s,1,RSTART-1)
        } else ext=""

        # 3. Strip trailing "standard"
        sub(/[-_ .]?[Ss]tandard$/, "", s)
	sub(/[-_ .]?[Dd]ecrypted$/, "", s)
	sub(/[-_ .]?[Pp]iratelegit$/, "", s)

        # 4. Move leading article BEFORE sanitization, while " - " is still intact
        #    "The Legend of Zelda - A Link Between Worlds (USA)"
        #    -> "Legend of Zelda - The - A Link Between Worlds (USA)"
        #    We insert ", Art" just before the first " - " if present, else at end
        if (match(s, /^(The|An|A) /)) {
            art=substr(s,1,RLENGTH-1)       # "The"
            rest=substr(s,RLENGTH+1)        # "Legend of Zelda - A Link..."
            dash=index(rest, " - ")
            if (dash > 0) {
                # Insert article just before the subtitle dash
                s=substr(rest,1,dash-1) " - " art " - " substr(rest,dash+3)
            } else {
                s=rest " - " art
            }
        }

        # 5. Now sanitize
        gsub(/\047/, "", s)
        gsub(/\([^)]*\)/, "", s)
        gsub(/ *- */, "-", s)
        gsub(/ /, "-", s)
        gsub(/\./, "", s)
        gsub(/[^A-Za-z0-9-]+/, "", s)
        gsub(/-+/, "-", s)
        gsub(/^-|-$/, "", s)

        print tolower(s) ext
    }')

    [ "$FINAL" != "$OUTPUT" ] && mv -- "jingles/n3ds/$OUTPUT" "jingles/n3ds/$FINAL"

    echo "Saved: $FINAL"
done
