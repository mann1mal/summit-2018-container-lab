# Deconstructing an Application into Microservices

In this lab you will deconstruct an application into microservices, creating a multi-container application. In this process we explore the challenges of networking, storage and configuration. We will use the containers we build in this lab for our OpenShift deployments in the upcoming labs.

This lab should be performed on **YOUR ASSIGNED AWS VM** as `ec2-user` unless otherwise instructed.

**Note**: In the steps below we use `vi` to edit files.  If you are unfamiliar this is a [good beginner's guide](https://www.howtogeek.com/102468/a-beginners-guide-to-editing-text-files-with-vi/).

Expected completion: 20-30 minutes

## Create the Dockerfiles

Now we will develop the two images. Using the information above and the Dockerfile from Lab 2 as a guide, we will create Dockerfiles for each service. For this lab we have created a directory for each service with the required files for the service. Please explore these directories and check out the contents and the startup scripts.

```bash
$ mkdir ~/workspace
$ cd ~/workspace
$ cp -R ~/summit-2018-container-lab/labs/lab3/mariadb .
$ cp -R ~/summit-2018-container-lab/labs/lab3/wordpress .
$ ls -lR mariadb
$ ls -lR wordpress
```

### MariaDB Dockerfile

* In a text editor create a file named `Dockerfile` in the `mariadb` directory. (There is a reference file in the `mariadb` directory if needed)

```bash
        $ vi mariadb/Dockerfile
```

* Add a `FROM` line that uses a specific image tag. Also add `MAINTAINER` information.

```bash
        FROM registry.access.redhat.com/rhel7:7.5-231
        MAINTAINER Student <student@example.com>
```

* Add the required packages. We'll include `yum clean all` at the end to clear the yum cache.

```bash
        RUN yum -y install --disablerepo "*" --enablerepo rhel-7-server-rpms \
              mariadb-server openssl psmisc net-tools hostname && \
            yum clean all
```
* Add the dependent scripts and modify permissions to support non-root container runtime.

```bash
        ADD scripts /scripts
        RUN chmod 755 /scripts/* && \
            MARIADB_DIRS="/var/lib/mysql /var/log/mariadb /run/mariadb" && \
            chown -R mysql:0 ${MARIADB_DIRS} && \
            chmod -R g=u ${MARIADB_DIRS}
```

* Add an instruction to expose the database port.

```bash
        EXPOSE 3306
```

* Add a `VOLUME` instruction. This ensures data will be persisted even if the container is lost. However, it won't do anything unless, when running the container, host directories are mapped to the volumes.

```bash
        VOLUME /var/lib/mysql
```

* Switch to a non-root `USER` uid. The default uid of the mysql user is 27.

```bash
        USER 27
```

* Finish by adding the `CMD` instruction.

```bash
        CMD ["/bin/bash", "/scripts/start.sh"]
```

* Save the file and exit the editor.

### Wordpress Dockerfile

Now we'll create the Wordpress Dockerfile. (As before, there is a reference file in the `wordpress` directory if needed)

* Using a text editor create a file named `Dockerfile` in the `wordpress` directory.

```bash
        $ vi wordpress/Dockerfile
```

* Add a `FROM` line that uses a specific image tag. Also add `MAINTAINER` information.

```bash
        FROM registry.access.redhat.com/rhel7:7.5-231
        MAINTAINER Student <student@example.com>
```

* Add the required packages. We'll include `yum clean all` at the end to clear the yum cache.

```bash
        RUN yum -y install --disablerepo "*" --enablerepo rhel-7-server-rpms \
              httpd php php-mysql php-gd openssl psmisc && \
            yum clean all
```

* Add the dependent scripts and make them executable.

```bash
        ADD scripts /scripts
        RUN chmod 755 /scripts/*
```

* Add the Wordpress source from gzip tar file. podman will extract the files. Also, modify permissions to support non-root container runtime. Switch to port 8080 for non-root apache runtime.

```bash
        COPY latest.tar.gz /latest.tar.gz
        RUN tar xvzf /latest.tar.gz -C /var/www/html --strip-components=1 && \
            rm /latest.tar.gz && \
            sed -i 's/^Listen 80/Listen 8080/g' /etc/httpd/conf/httpd.conf && \
            APACHE_DIRS="/var/www/html /usr/share/httpd /var/log/httpd /run/httpd" && \
            chown -R apache:0 ${APACHE_DIRS} && \
            chmod -R g=u ${APACHE_DIRS}
```

* Add an instruction to expose the web server port.

```bash
        EXPOSE 8080
```

* Add a `VOLUME` instruction. This ensures data will be persisted even if the container is lost.

```bash
        VOLUME /var/www/html/wp-content/uploads
```

* Switch to a non-root `USER` uid. The default uid of the apache user is 48.

```bash
        USER 48
```

* Finish by adding the `CMD` instruction.

```bash
        CMD ["/bin/bash", "/scripts/start.sh"]
```

* Save the Dockerfile and exit the editor.

## Build Images, Test and Push

Now we are ready to build the images to test our Dockerfiles.

* Build each image. When building an image docker requires the path to the directory of the Dockerfile.

```bash
        $ docker build -t mariadb mariadb/
        $ docker build -t wordpress wordpress/
```

* If the build does not return `Successfully built <image_id>` then resolve the issue and build again. Once successful, list the images.

```bash
        $ docker images
```

* Create the local directories for persistent storage & set permissions for container runtime.

```bash
        $ mkdir -p ~/workspace/pv/mysql ~/workspace/pv/uploads
        $ sudo chown -R 27 ~/workspace/pv/mysql
        $ sudo chown -R 48 ~/workspace/pv/uploads
```

* Run the wordpress image first. It takes some time to discover all of the necessary `docker run` options.

  * `-d` to run in daemonized mode
  * `-v <host/path>:<container/path>:z` to mount (technically, "bindmount") the directory for persistent storage. The :z option will label the content inside the container with the SELinux MCS label that the container uses so that the container can write to the directory. Below we'll inspect the labels on the directories before and after we run the container to see the changes on the labels in the directories
  * `-p <host_port>:<container_port>` to map the container port to the host port

```bash
$ ls -lZd ~/workspace/pv/uploads
$ docker run -d -p 8080:8080 -v ~/workspace/pv/uploads:/var/www/html/wp-content/uploads:z -e DB_ENV_DBUSER=user -e DB_ENV_DBPASS=mypassword -e DB_ENV_DBNAME=mydb -e DB_HOST=0.0.0.0 -e DB_PORT=3306 --name wordpress wordpress
```

**Note**: See the difference in SELinux context after running w/ a volume & :Z.

```bash
$ ls -lZd ~/workspace/pv/uploads
$ docker exec $(docker ps -ql) ps aux
```

* Check volume directory ownership inside the container

```bash
$ docker exec $(docker ps -ql) stat --format="%U" /var/www/html/wp-content/uploads
$ docker logs $(docker ps -ql)
$ docker ps
$ curl -L http://localhost:8080
```

  **Note**: the `curl` command does not return useful information but demonstrates
            a response on the port.

* Bring up the database (mariadb) for the wordpress instance. For the mariadb container we need to specify an additional option to make sure it is in the same "network" as the apache/wordpress container and not visible outside that container:

  * `--network=container:<alias>` to link to the wordpress container
    
```bash
$ ls -lZd ~/workspace/pv/mysql
$ docker run -d --network=container:wordpress -v ~/workspace/pv/mysql:/var/lib/mysql:z -e DBUSER=user -e DBPASS=mypassword -e DBNAME=mydb --name mariadb mariadb
```

**Note**: See the difference in SELinux context after running w/ a volume & :z.

```bash
$ ls -lZd ~/workspace/pv/mysql
$ ls -lZ ~/workspace/pv/mysql
$ docker exec $(docker ps -ql) ps aux
```

* Check volume directory ownership inside the container

```bash
$ docker exec $(docker ps -ql) stat --format="%U" /var/lib/mysql
```

* Now we can check out how the database is doing

```bash
$ docker logs $(docker ps -ql)
$ docker ps
$ curl localhost:3306 #as you can see the db is not generally visible
$ curl -L http://localhost:8080 #and now wp is happier!
```

You may also load the Wordpress application in a browser to test its full functionality @ `http://<YOUR AWS VM PUBLIC DNS NAME HERE>:8080`.

## Deploy a Container Registry

To prepare for a later lab, let's deploy a simple registry to store our images.

Navigate to the Lab3 directory

```bash
$ cd ~/summit-2018-container-lab/labs/lab3
```

Inspect the Dockerfile that has been prepared.

```bash
$ cat registry/Dockerfile
```

Build & run the registry

```bash
$ docker build -t registry registry/
$ docker run --restart="always" --name registry -p 5000:5000 -d registry
```

Confirm the registry is running.

```bash
$ docker ps
```

### Push images to local registry

* Once satisfied with the images tag them with the URI of the local lab local registry. The tag is what OpenShift uses to identify the particular image that we want to import from the registry.

        ```
        $ docker tag mariadb localhost:5000/mariadb
        $ docker tag wordpress localhost:5000/wordpress
        $ docker images
        ```
* Push the images
        ```
        $ docker push localhost:5000/mariadb
        $ docker push localhost:5000/wordpress
        ```
## Clean Up

* Stop the mariadb and wordpress containers.

```bash
$ docker ps
$ docker stop mariadb wordpress
```

* After iterating through running docker images you will likely end up with many stopped containers. List them.

```bash
$ docker ps -a
```

* This command is useful in freeing up disk space by removing all stopped containers.

```bash
$ docker rm $(docker ps -qa)
```

This command will result in a cosmetic error because it is trying to stop running containers like the registry and the OpenShift containers that are running. These errors can safely be ignored.


In the next we introduce container orchestration via OpenShift.
