#!/bin/bash

# Install netcat if not already installed
if ! command -v nc &> /dev/null; then
    echo "Installing netcat..."
    apt-get update
    apt-get install -y netcat
fi

# Install netstat if not already installed
if ! command -v netstat &> /dev/null; then
    echo "Installing net-tools..."
    apt-get update
    apt-get install -y net-tools
fi

echo "Installing required packages..."
echo
echo
pip install -r requirements.txt

echo
echo
echo "ComfyUI Launcher is starting..."
echo
echo

cd server/

# start Celery worker in the bg
celery -A server.celery_app --workdir=. worker --loglevel=DEBUG &
celery_worker_pid=$!
echo "Celery worker started with PID: $celery_worker_pid"

# Install localtunnel
echo "Installing localtunnel..."
npm install -g localtunnel

# Find an open port
find_open_port() {
  local port=8188
  while netstat -tulnp | grep -q ":$port "; do
    port=$((port + 1))
  done
  echo $port
}

PORT=$(find_open_port)

# Run server.py in the background and redirect output to a file
python server.py --port $PORT > server.log 2>&1 &
server_pid=$!
echo "ComfyUI server started with PID: $server_pid on port $PORT"

# Function to check if ComfyUI is running
is_comfyui_running() {
  timeout 10 bash -c "until nc -z localhost $PORT; do sleep 0.1; done"
}

# Wait for ComfyUI to start
echo "Waiting for ComfyUI to start..."
if is_comfyui_running; then
  echo "ComfyUI is running, launching localtunnel..."
  # Get the external IP address
  EXTERNAL_IP=$(curl -s https://ipv4.icanhazip.com)
  echo "The password/endpoint IP for localtunnel is: $EXTERNAL_IP"

  # Run localtunnel and capture the URL
  echo "Launching localtunnel..."
  EXTERNAL_IP=$(curl -s https://ipv4.icanhazip.com)
  echo "The password/endpoint IP for localtunnel is: $EXTERNAL_IP"
  LOCALTUNNEL_URL=$(lt --port $PORT 2>&1 | grep "your url is:" | tail -n 1 | awk '{print $4}')

  if [ -n "$LOCALTUNNEL_URL" ]; then
    echo "ComfyUI is accessible via: $LOCALTUNNEL_URL"
  else
    echo "Failed to retrieve Localtunnel URL."
  fi
else
  echo "ComfyUI failed to start."
fi

# kill Celery worker when server.py is done
kill $celery_worker_pid
kill $server_pid
