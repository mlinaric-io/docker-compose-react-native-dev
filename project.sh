#! /bin/bash

if ! (( "$OSTYPE" == "gnu-linux" )); then
  echo "docker-compose-react-native-dev runs only on GNU/Linux operating system. Exiting..."
  exit
fi

###############################################################################
# 1.) Assign variable
###############################################################################

  #PROJECT_NAME is parent directory
  PROJECT_NAME=`printf '%s\n' "${PWD##*/}" | tr -cd '[:alnum:]_'`
  PROJECT_UID=`id -u`
  PROJECT_GID=`id -g`
  
  USER=node
  
  PROJECT_AUTHOR=`git config user.name`
  PROJECT_EMAIL=`git config user.email`

############################ BUILD SUBROUTINE #################################

build() {
  mkdir -p  $PROJECT_NAME/android/app/src/main/assets
  docker-compose run node sh -c "cd $PROJECT_NAME && \
yarn react-native bundle --platform android --dev false --entry-file index.js --bundle-output android/app/src/main/assets/index.android.bundle --assets-dest android/app/src/main/res"
  docker-compose run android-sdk sh -c "cd $PROJECT_NAME/android && ./gradlew assembleDebug"
}
############################ CLEAN SUBROUTINE #################################

clean() {
  docker-compose stop
  docker system prune -af --volumes
  rm -rf Android/ \
    .android/ \
    .cache/ \
    .config/ \
    .gradle/ \
    .kotlin/ \
    .local/ \
    .pki/ \
    .yarn/ \
    51-android.rules \
    docker-compose.yml \
    docker_entrypoint.sh \
    Dockerfile \
    ndkTests.sh \
    .emulator_console_auth_token \
    $PROJECT_NAME/node_modules/
  find ./**/android -name 'build' -type d -prune -print -exec rm -rf '{}' \;
} 

############################ START SUBROUTINE #################################

start() {
  
  mkdir -p .android docs

###############################################################################
# 2.) Generate configuration files
###############################################################################

if [[ ! -f .gitignore ]]; then
  touch .gitignore && \
  cat <<-'EOF' > .gitignore
# Android
Android/
.android/
.gradle/
.kotlin/
# generated in project.sh
51-android.rules 
# generated in project.sh
ndkTests.sh

# .cache folder
.cache/

# yarn
.config/
.yarn/

# docs folder
docs/

# Docker - generated in project.sh
docker-compose.yml
docker_entrypoint.sh
Dockerfile

# .emulator_console_auth_token
.emulator_console_auth_token
EOF
fi

if [[ ! -f 51-android.rules ]]; then
  touch 51-android.rules && \
  cat <<-'EOF' > 51-android.rules
  SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="6860", MODE="0660",
  GROUP="plugdev", SYMLINK+="android%n"
EOF
fi

if [[ ! -f docker_entrypoint.sh ]]; then
  touch docker_entrypoint.sh && \
  cat <<-'EOF' > docker_entrypoint.sh
  #!/bin/bash

  #Change permissions of /dev/kvm for Android Emulator
  echo "`whoami`" | sudo -S chmod 777 /dev/kvm > /dev/null 2>&1

  export PATH=$PATH:/home/node/gradle/bin:/home/node/kotlinc/bin:/home/node/Android/Sdk/cmdline-tools/latest/bin:/home/node/Android/Sdk/emulator:/home/node/Android/Sdk/platform-tools:/home/node/Android/Sdk/cmdline-tools/tools/bin:/home/node/android-sdk/jre/bin


  if [ "${1#-}" != "${1}" ] || [ -z "$(command -v "${1}")" ]; then
    set -- android-sdk "$@"
  fi

  exec "$@"
EOF
fi

if [[ ! -f ndkTests.sh ]]; then
  touch ndkTests.sh && \
  cat <<-'EOF' > ndkTests.sh
#!/bin/bash
  # This sript will install our Google Tests on an Android device.
  # If needed the script will start an Emulator beforehand.
  #It will then run those tests and analyze the results.
  #Will return 0 if everything succeeded.
  #If there were failed tests it will return the number of failed tests

  #Ensure server is started
  ADB="/studio-data/Android/Sdk/platform-tools/adb"
  "$ADB" start-server || exit 1

  if [ "$("$ADB" devices | grep device | wc -l)" -lt 2 ] ; then
    echo "No device found - starting Emulator"
    if [ "$HOSTNAME" = "CI" ]; then
      #Start a virtual framebuffer for continous integration, as we do not have a Display attached
      echo "Starting xvfb for CI..."
      Xvfb :1 &
      export DISPLAY=:1
      #Does not seem to work with GPU, so turn gpu processing off (slower)
      /studio-data/emulator/emulator -avd Nexus_5_API_24 -gpu off > android_emulator_log.txt 2>&1 &
    else
      /studio-data/emulator/emulator -avd Nexus_5_API_24 > android_emulator_log.txt 2>&1 &
    fi
    #/studio-data/emulator/emulator -avd Android_O &
    echo "Will now wait for the Emulator"
    #/studio-data/platform-tools/adb wait-for-device -s `/studio-data/platform-tools/adb devices | grep emulator`
    while (! "$ADB" devices | grep emulator | grep device > /dev/null); do sleep 1; echo -n "."; done
  fi
  device=$("ADB" devices | grep -Po ".*(?= *device$)" | head -n1)
  if [ "$device" = "" ]; then
    echo "Error in acquiring device, exiting..."
    exit 1
  fi
  echo "Found a device \"$device\" to use"

  #Install our tests
  pushd /studio-data/workspace/GoogleTestApp/
  #Build and install our app(s)
  ./gradlew installDebug || exit 1
  #clean, assembleDebug, generateDebugSources
  popd
  #Clear old logcat data
  "$ADB" -s $device logcat -c || exit 1
  #(Force-)Start our tests
  "$ADB" -s $device shell am start -S -n com.example.company.testApp/com.example.company.testApp.MainActivity

  #Wait for the latest adb log data to arrive
  while [ $("$ADB" -s $device logcat -d -s "GoogleTest" | grep "End Result" | wc -l) -lt 2 ] ; do
  sleep 0.5
  done

  #Get our data from logcat and save it
  "$ADB" -s $device logcat -d -s "GoogleTest" > test_results.txt || exit 1

  #Uninstall our Tests again
  pushd /studio-data/workspace/GoogleTestAndroidGnssHal/
  ./gradlew uninstallDebug || exit 1
  popd

  #Filter out the failed tests from the log file we pulled
  failed_tests=`cat test_results.txt | grep -P -o '\d+(?= Test\(s\) failed --> .*Failed)' | awk 'BEGIN {t=0} {t+=$1} END { print t}'`
  if [ "$failed_tests" -gt 0 ]; then
    echo "$failed_tests tests failed"
    else
    echo "All tests passed"
    exit 0
  fi

  "$ADB" -s $device emu kill
  while ("$ADB" devices | grep $device > /dev/null) ; do
  sleep 0.5
  done


  exit $failed_tests
EOF
fi


if [[ ! -f Dockerfile ]]; then
  touch Dockerfile && \
  cat <<EOF> Dockerfile
  FROM debian:buster

  ENV DEBIAN_FRONTEND=noninteractive
  ENV USER=node

  RUN dpkg --add-architecture i386
  RUN apt-get update && apt-get install -y \
    bash build-essential git neovim wget curl openjdk-11-jdk unzip sudo \
    libc6:i386 libncurses5:i386 libstdc++6:i386 lib32z1 libbz2-1.0:i386 \
    libxrender1 libxtst6 libxi6 libfreetype6 libxft2 \
    qemu qemu-kvm libvirt-daemon-system bridge-utils libnotify4 libglu1 libqt5widgets5 xvfb \
    && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

  RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get update -qq \
    && apt-get install -qq -y --no-install-recommends nodejs \
    && npm i -g yarn \
    && rm -rf /var/lib/apt/lists/*

  RUN groupadd -g $PROJECT_GID -r $USER
  RUN useradd -u $PROJECT_UID -g $PROJECT_GID --create-home -r $USER
  RUN adduser $USER libvirt
  RUN adduser $USER kvm
  #Change password
  RUN echo "$USER:$USER" | chpasswd
  #Make sudo passwordless
  RUN echo "${USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$USER
  RUN usermod -aG sudo $USER
  RUN usermod -aG plugdev $USER

  COPY docker_entrypoint.sh /usr/local/bin/
  COPY ndkTests.sh /usr/local/bin/ndkTests.sh
  RUN chmod +x /usr/local/bin/*
  COPY 51-android.rules /etc/udev/rules.d/51-android.rules

  USER $USER

  WORKDIR /home/$USER

  ENV ANDROID_EMULATOR_USE_SYSTEM_LIBS=1
  ENV ANDROID_SDK_ROOT /home/node/Android/Sdk
  ENV JAVA_HOME /usr/lib/jvm/java-1.11.0-openjdk-amd64
  ENV GRADLE_HOME /home/node/gradle
  ENV KOTLIN_HOME /home/node/kotlinc

  ENV PATH ${PATH}:/home/node/gradle/bin:/home/node/kotlinc/bin:/home/node/Android/Sdk/cmdline-tools/latest/bin:/home/node/Android/Sdk/emulator:/home/node/Android/Sdk/platform-tools:/home/node/Android/Sdk/cmdline-tools/tools/bin:/usr/lib/jvm/java-1.11.0-openjdk-amd64/bin

  CMD [ "sdkmanager" ]
EOF
fi

if [[ ! -f docker-compose.yml ]]; then
  cat <<EOF> docker-compose.yml
  version: "3.8"

  services:
    android-sdk:
      build: .
      image: android-sdk
      user: $PROJECT_UID:$PROJECT_GID
      working_dir: /home/node
      environment:
        DISPLAY: $DISPLAY
      volumes:
        - .:/home/node
        - /tmp/.X11-unix:/tmp/.X11-unix
        - /dev/kvm:/dev/kvm
        - /dev/bus/usb:/dev/bus/usb
      network_mode: host
      privileged: true
        
    node:
      image: node:16.15.0-alpine
      user: $PROJECT_UID:$PROJECT_GID
      working_dir: /home/node
      volumes:
        - .:/home/node
        - /tmp/.X11-unix:/tmp/.X11-unix
        - /dev/kvm:/dev/kvm
        - /dev/bus/usb:/dev/bus/usb
      environment:
        NODE_ENV: development
      network_mode: host
      privileged: true
EOF
fi

###############################################################################
# 4.) Install dependencies
###############################################################################

  if [[ ! -d $PROJECT_NAME ]]; then
  
    # generate .git folder with initial commit
    rm -rf .git
    git init
    git add .
    git commit -m "feat: initial commit"

    # initialize project
    docker-compose run node yarn global add ynpx react-native cli
    docker-compose run node yarn exec react-native init $PROJECT_NAME
  else
    docker-compose run node sh -c "cd $PROJECT_NAME && yarn install"
  fi
    
  if [[ ! -d Android ]]; then
    mkdir -p Android/Sdk/cmdline-tools
    wget -q https://dl.google.com/android/repository/commandlinetools-linux-7302050_latest.zip
    unzip *tools*linux*.zip -d Android/Sdk/cmdline-tools
    mv Android/Sdk/cmdline-tools/cmdline-tools Android/Sdk/cmdline-tools/tools
    rm *tools*linux*.zip
  fi
    
  docker-compose run android-sdk bash -c "yes | sdkmanager --licenses && sdkmanager --list"
    
  docker-compose run android-sdk bash -c "sdkmanager 'build-tools;30.0.2';
                                          sdkmanager 'platforms;android-31';
                                          sdkmanager 'platform-tools';
                                          sdkmanager 'system-images;android-31;google_apis;x86_64';
                                          adb devices;
                                          avdmanager list;
                                          avdmanager list avd;"
                                        
  docker-compose run android-sdk bash -c "echo no | avdmanager create avd --force --name  'TestAPI31' --abi google_apis/x86_64 --package 'system-images;android-31;google_apis;x86_64'"
  sleep 10
  `ls /usr/bin | grep terminal` -e "docker-compose run android-sdk bash -c 'adb start-server && emulator @TestAPI31 -dns-server 8.8.8.8'"
  sleep 10
  `ls /usr/bin | grep terminal` -e "docker-compose run node sh -c 'cd $PROJECT_NAME && yarn exec react-native start'"
  sleep 10
  `ls /usr/bin | grep terminal` -e "docker-compose run android-sdk bash -c 'cd $PROJECT_NAME && yarn exec react-native run-android'"
}

"$1"
