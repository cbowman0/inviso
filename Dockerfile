FROM inetsoftware/ubuntu-java-gradle
MAINTAINER Jash Lee <s905060@gmail.com>

# install required dependencies
#
RUN apt-get update && apt-get install -y wget curl vim git python-pip supervisor
RUN pip install --upgrade pip ; \
	pip install virtualenv

# installation will take place in /opt
#
ENV TARGET /opt

# unfortunately, docker doesn't support string interpolation in WORKDIR
#
WORKDIR /opt

# install tomcat
#
ENV TOMCAT_VERSION 7.0.82
RUN wget -qq http://mirror.jax.hugeserver.com/apache/tomcat/tomcat-7/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz ; \
	tar -xzvf apache-tomcat-${TOMCAT_VERSION}.tar.gz ; \
	rm -r apache-tomcat-${TOMCAT_VERSION}/webapps/* ; \
	rm apache-tomcat-${TOMCAT_VERSION}.tar.gz ; \
	ln -s apache-tomcat-${TOMCAT_VERSION} /opt/apache-tomcat 

# install elastic search
#
ENV ELASTICSEARCH_VERSION 1.3.2
RUN wget -qq http://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz ; \
	tar -xzvf elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz ; \
	rm elasticsearch-${ELASTICSEARCH_VERSION}.tar.gz

# INVISO_COMMIT_HASH allows us to specify the exact version of inviso this container will build
#
ENV INVISO_COMMIT_HASH 30b445c4221ecdcf432f4009e176f80a7c922dbd

# clone the inviso repo and build the project
#
RUN git clone https://github.com/s905060/inviso.git ; \
	(cd inviso; git reset --hard ${INVISO_COMMIT_HASH} ; ./gradlew assemble) 
RUN cp "${TARGET}/inviso/trace-mr2/build/libs/inviso#mr2#v0.war" ${TARGET}/apache-tomcat-${TOMCAT_VERSION}/webapps/ ; \
	ln -s ${TARGET}/inviso/web-ui/public ${TARGET}/apache-tomcat-${TOMCAT_VERSION}/webapps/ROOT

# install jes
RUN pip install -r inviso/jes/requirements.txt ; \
	cp inviso/jes/settings_default.py inviso/jes/settings.py

RUN ["/bin/bash", "-c", "while true; do sleep 60s; python jes.py; done&"]
RUN ["/bin/bash", "-c", "while true; do sleep 60s; python index_cluster_stats.py; done&"]

# configure elasticsearch to point to inviso
#
# NOTE: for some reason the -p flag inside a docker build doesn't write out the pidfile :\
#
RUN ${TARGET}/elasticsearch-${ELASTICSEARCH_VERSION}/bin/elasticsearch -d ; \
	curl -XPUT http://localhost:9200/inviso -d @${TARGET}/inviso/elasticsearch/mappings/config-settings.json ; \
	curl -XPUT http://localhost:9200/inviso-cluster -d @${TARGET}/inviso/elasticsearch/mappings/cluster-settings.json ; \
	kill -9 `ps auxww | grep java | grep -v grep | awk '{print $2}'`

ENV SERVICE_CONF /etc/supervisor/conf.d/services.conf
RUN echo '[program:elasticsearch]' >> ${SERVICE_CONF} ; \
	echo "command=${TARGET}/elasticsearch-${ELASTICSEARCH_VERSION}/bin/elasticsearch" >> ${SERVICE_CONF} ; \
	echo '' >> ${SERVICE_CONF} ; \
	echo '[program:tomcat]' >> ${SERVICE_CONF} ; \
	echo "command=${TARGET}/apache-tomcat-${TOMCAT_VERSION}/bin/catalina.sh run" >> ${SERVICE_CONF} ; \
	echo '' >> ${SERVICE_CONF}

# additional scripting for the boot sequence
EXPOSE 8080

CMD [ "/usr/bin/supervisord", "--nodaemon" ]


