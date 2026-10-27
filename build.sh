#!/bin/sh
# Usage: ./build.sh            build into build/
#        ./build.sh --install  build, copy to /Applications and launch
set -e
cd "$(dirname "$0")"
APP=build/StopMissingMeetings.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/StopMissingMeetings"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
if [ "$1" = "--install" ]; then
  pkill -x StopMissingMeetings || true
  rm -rf /Applications/StopMissingMeetings.app
  cp -R "$APP" /Applications/
  open /Applications/StopMissingMeetings.app
  echo "Installed and launched"
fi
