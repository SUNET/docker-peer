FROM ubuntu:14.04
MAINTAINER Leif Johansson <leifj@sunet.se>
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get update
RUN apt-get install -y git-core build-essential python-dev libxml2-dev libxml2 libxslt1-dev libxslt1.1 xmlsec1 libxmlsec1-openssl libpq-dev libz-dev python-virtualenv apache2 ssl-cert libapache2-mod-wsgi
RUN a2enmod rewrite
RUN a2enmod ssl
RUN a2enmod headers
RUN a2enmod wsgi
RUN virtualenv /var/www/peer --no-site-packages
ENV VENV /var/www/peer
WORKDIR /var/www/peer
ADD wsgi.conf /etc/apache2/conf-available/wsgi.conf
RUN a2enconf wsgi
ADD invenv.sh /invenv.sh
RUN chmod a+x /invenv.sh
ADD opt /opt/peer
RUN /invenv.sh pip install git+git://github.com/Yaco-Sistemas/peer.git#egg=peer
RUN ln -s /opt/peer/local_settings.py /var/www/peer/lib/python2.7/site-packages/peer/local_settings.py
RUN rm -f /etc/apache2/sites-available/*
RUN rm -f /etc/apache2/sites-enabled/*
ADD start.sh /start.sh
RUN chmod a+x /start.sh
ENV SP_HOSTNAME reep.example.org
ENV SP_CONTACT info@example.org
ENV SP_ABOUT /about
EXPOSE 443
EXPOSE 80
ENTRYPOINT ["/start.sh"]
CMD ["start"]
