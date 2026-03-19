#!/bin/bash

if [ $# -lt 3 ]; then
    echo "Usage: $0 <file> <server_url> <upload_id>"
    exit 1
fi

FILE="$1"
SERVER="$2"
UPLOAD_ID="$3"

USER_NAME=$(whoami)

CHUNK_SIZE="5M"
SPLIT_PREFIX="chunk_"

UPLOAD_COMPLETE=0

# Validate file exists
if [ ! -f "$FILE" ]; then
    echo "[!] File not found: $FILE"
    exit 1
fi

echo "[*] File: $FILE"
echo "[*] Upload ID: $UPLOAD_ID"

# --- SPLIT FILE (NUMERIC CHUNKS) ---
if [ ! -f "${SPLIT_PREFIX}00" ]; then
    echo "[*] Splitting file into chunks..."
    split -d -b $CHUNK_SIZE "$FILE" $SPLIT_PREFIX
fi

TOTAL=$(ls ${SPLIT_PREFIX}* 2>/dev/null | wc -l)

if [ "$TOTAL" -eq 0 ]; then
    echo "[!] No chunks found. Exiting."
    exit 1
fi

echo "[*] Total chunks: $TOTAL"

# --- QUERY SERVER FOR RESUME ---
UPLOADED=$(curl -s "$SERVER/status?upload_id=$UPLOAD_ID&user=$USER_NAME" \
    | jq -r '.uploaded_chunks[]' 2>/dev/null)

echo "[*] Already uploaded chunks: $UPLOADED"

INDEX=0

for f in ${SPLIT_PREFIX}*; do

    if echo "$UPLOADED" | grep -q "^$INDEX$"; then
        echo "[*] Skipping chunk $INDEX"
    else
        echo "[*] Uploading chunk $INDEX"

        RESPONSE=$(curl -s -X POST "$SERVER/upload" \
            -F "file=@$f" \
            -F "filename=$(basename $FILE)" \
            -F "chunk_index=$INDEX" \
            -F "total_chunks=$TOTAL" \
            -F "upload_id=$UPLOAD_ID" \
            -F "user=$USER_NAME")

        echo "[*] Server response: $RESPONSE"
	# Detect final chunk completion
	if echo "$RESPONSE" | grep -q "File reassembled"; then
	    UPLOAD_COMPLETE=1
	fi

        # Sleep + jitter (1–5 seconds)
        SLEEP_TIME=$((1 + RANDOM % 5))
        echo "[*] Sleeping $SLEEP_TIME seconds"
        sleep $SLEEP_TIME
    fi

    INDEX=$((INDEX+1))
done

# --- FINAL CHECK BEFORE CLEANUP ---
echo "[*] Verifying upload completion..."

if [ "$UPLOAD_COMPLETE" -eq 1 ]; then
    echo "[*] Upload complete. Cleaning up chunk files..."
    rm -f ${SPLIT_PREFIX}*
    echo "[*] Cleanup done."
else
    echo "[!] Upload incomplete. Keeping chunks for resume."
fi
