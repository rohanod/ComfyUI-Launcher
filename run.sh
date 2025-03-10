#!/bin/bash

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

  # Run localtunnel in the background
  lt --port $PORT &
  localtunnel_pid=$!
  echo "Localtunnel started with PID: $localtunnel_pid"

  # Get the localtunnel URL from the logs
  sleep 5 # Give localtunnel some time to start
  LOCALTUNNEL_URL=$(grep "your url is:" server.log | tail -n 1 | awk '{print $4}')

  if [ -n "$LOCALTUNNEL_URL" ]; then
    echo "ComfyUI is accessible via: $LOCALTUNNEL_URL"
  else
    echo "Failed to retrieve Localtunnel URL. Check server.log for errors."
  fi
else
  echo "ComfyUI failed to start."
fi

# kill Celery worker when server.py is done
kill $celery_worker_pid
kill $server_pid
if [ -n "$localtunnel_pid" ]; then
  kill $localtunnel_pid
fi
