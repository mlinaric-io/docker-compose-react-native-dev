# docker-compose-react-native-dev

Container(ed) development environment for react-native apps

## Requirements

- GNU/Linux OS
- docker (with docker-compose)

## Usage

1.) Clone the project with:
```bash
git clone https://github.com/mlinaric-io/docker-compose-react-native-dev
```

2.) Rename the project root folder "docker-compose-react-native-dev" to the
preferred name of your project:
```bash
mv docker-compose-react-native-dev myamazingproject
```

3.) Make project.sh executable:
```bash
chmod +x myamazingproject/project.sh
```

4.) Move into "myamazingproject" and run "project.sh start" to download and 
start everything necessary (~14Gb) for the basic react-native development 
environment with emulators and/or physical devices:
WARNING AGAIN: It will take a lot of time and bandwidth!
```bash
cd myamazingproject && ./project.sh start
```

5.) Code your new app in "myamazingproject/myamazingproject" folder.

Additional options:

You might need to do a bit of tweaking in "project.sh", but you can build your
app with:
```bash
cd myamazingproject && ./project.sh build
```

When you finish your hardworking day, you might want to gently stop the ecosystem:
```bash
cd myamazingproject && docker-compose stop
``` 
or remove the development ecosystem completely and save only the code of your project:
```bash
cd myamazingproject && ./project.sh clean
```

You can run existing projects with step 4.

## License

docker-compose-react-native-dev is licensed under [MIT license](LICENSE)
