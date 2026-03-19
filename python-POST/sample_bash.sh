TOTAL=$(ls chunk_* | wc -l)
INDEX=0

for f in chunk_*; do
  curl -X POST http://<SERVER_IP>:5000/upload \
    -F "file=@$f" \
    -F "filename=yourfile.zip" \
    -F "chunk_index=$INDEX" \
    -F "total_chunks=$TOTAL"

  INDEX=$((INDEX+1))
done
