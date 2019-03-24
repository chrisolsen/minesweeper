_build: build.sh
    rm -rf build
    java -jar bob.jar -a -v

android: _build
    echo "buidling for android"

web: _build
    echo "buidling for web"

ios: _build
    echo "buidling for ios"

all: android web ios
    echo "building for all"