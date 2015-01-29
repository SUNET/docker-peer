#!/bin/sh -x

if [ "x$SP_HOSTNAME" = "x" ]; then
   SP_HOSTNAME="reep.refeds.org"
fi

if [ "x$SP_CONTACT" = "x" ]; then
   SP_CONTACT="info@example.com"
fi

if [ "x$SP_ABOUT" = "x" ]; then
   SP_ABOUT="/about"
fi

export DB_PORTNUMBER="5432"
export DB_HOSTNAME="localhost"
if [ "x${DB_PORT}" != "x" ]; then
   DB_HOSTNAME=`echo "${DB_PORT}" | sed 's%/%%g' | awk -F: '{ print $2 }'`
   DB_PORTNUMBER=`echo "${DB_PORT}" | sed 's%/%%g' | awk -F: '{ print $3 }'`
fi

KEYDIR=/etc/ssl
mkdir -p $KEYDIR
export KEYDIR

if [ ! -f "$KEYDIR/private/${SP_HOSTNAME}.key" -o ! -f "$KEYDIR/certs/${SP_HOSTNAME}.crt" ]; then
   make-ssl-cert generate-default-snakeoil --force-overwrite
   cp /etc/ssl/private/ssl-cert-snakeoil.key "$KEYDIR/private/${SP_HOSTNAME}.key"
   cp /etc/ssl/certs/ssl-cert-snakeoil.pem "$KEYDIR/certs/${SP_HOSTNAME}.crt"
fi

CHAINSPEC=""
export CHAINSPEC
if [ -f "$KEYDIR/certs/${SP_HOSTNAME}.chain" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${SP_HOSTNAME}.chain"
elif [ -f "$KEYDIR/certs/${SP_HOSTNAME}-chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${SP_HOSTNAME}-chain.crt"
elif [ -f "$KEYDIR/certs/${SP_HOSTNAME}.chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/${SP_HOSTNAME}.chain.crt"
elif [ -f "$KEYDIR/certs/chain.crt" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/chain.crt"
elif [ -f "$KEYDIR/certs/chain.pem" ]; then
   CHAINSPEC="SSLCertificateChainFile $KEYDIR/certs/chain.pem"
fi

cat>/etc/apache2/sites-available/default.conf<<EOF
<VirtualHost *:80>
       ServerAdmin ${SP_CONTACT}
       ServerName ${SP_HOSTNAME}
       DocumentRoot /var/www/

       RewriteEngine On
       RewriteCond %{HTTPS} off
       RewriteRule !/server-status$ https://%{HTTP_HOST}%{REQUEST_URI}
</VirtualHost>
EOF

cat>/etc/apache2/sites-available/default-ssl.conf<<EOF
<VirtualHost *:443>
        ServerName ${SP_HOSTNAME}
        SSLProtocol TLSv1 
        SSLEngine On
        SSLCertificateFile $KEYDIR/certs/${SP_HOSTNAME}.crt
        ${CHAINSPEC}
        SSLCertificateKeyFile $KEYDIR/private/${SP_HOSTNAME}.key

        <Location />
           Order deny,allow
           Allow from all
        </Location>

        <Directory /usr/www/peer>
           WSGIProcessGroup peer
           WSGIApplicationGroup %{GLOBAL}
           Order deny,allow
           Allow from all
        </Directory>

        ServerName ${SP_HOSTNAME}
        ServerAdmin noc@nordu.net

        AddDefaultCharset utf-8

        ErrorLog /var/log/apache2/error.log
        LogLevel warn
        CustomLog /var/log/apache2/access.log combined
</VirtualHost>
EOF

if [ ! -f /opt/peer/local_settings.py ]; then
SECRET=`tr -dc A-Za-z0-9_ < /dev/urandom | head -c 40 | xargs`
cat>/opt/peer/local_settings.py<<EOF
import os
import saml2

import logging
logging.basicConfig()
logger = logging.getLogger("djangosaml2")
logger.setLevel(logging.DEBUG)

BASEDIR = os.path.abspath(os.path.dirname(__file__))

ADMINS = (
    ('Peer Admin', '${SP_CONTACT}'),
)

EMAIL_HOST = 'localhost'
EMAIL_PORT = 25

#RECAPTCHA_PUBLIC_KEY = '<Define before enabling recaptcha>'
#RECAPTCHA_PRIVATE_KEY = '<Define before enabling recaptcha>'
#RECAPTCHA_USE_SSL = True

DEFAULT_FROM_EMAIL = 'no-reply@example.com'
SECRET_KEY = '${SECRET}'

VFF_REPO_ROOT = '/opt/peer/vf_repo'

DEBUG = True
TEMPLATE_DEBUG = DEBUG

ENTITIES_PER_PAGE = 10

PEER_HOST = '${SP_HOSTNAME}'
PEER_PORT = '443'
PEER_BASE_URL = 'https://' + PEER_HOST

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql_psycopg2',
        'NAME': 'postgres',
        'USER': 'postgres',
        'PASSWORD': 'postgres',
        'HOST': 'db',
        'PORT': '',
    }
}

SAML_ENABLED = True
SESSION_EXPIRE_AT_BROWSER_CLOSE = SAML_ENABLED
SAML_CREATE_UNKNOWN_USER = True
SAML_ATTRIBUTE_MAPPING = {
    'mail': ('username', 'email'),
    'givenName': ('first_name', ),
    'sn': ('last_name', ),
}

SAML_CONFIG = {
    # full path to the xmlsec1 binary programm
    'xmlsec_binary': '/usr/bin/xmlsec1',

    # your entity id, usually your subdomain plus the url to the metadata view
    'entityid': PEER_BASE_URL + '/saml2/metadata/',

    # directory with attribute mapping
    'attribute_map_dir': '/opt/peer/pysaml2/attributemaps',

    # this block states what services we provide
    'service': {
        # we are just a lonely SP
        'sp' : {
            'name': 'REEP',
            'endpoints': {
                # url and binding to the assetion consumer service view
                # do not change the binding or service name
                'assertion_consumer_service': [
                    (PEER_BASE_URL + '/saml2/acs/', saml2.BINDING_HTTP_POST),
                  ],
                # url and binding to the single logout service view
                # do not change the binding or service name
                'single_logout_service': [
                    (PEER_BASE_URL + '/saml2/ls/', saml2.BINDING_HTTP_REDIRECT),
                    ],
                },

            # attributes that this project need to identify a user
            'required_attributes': ['mail'],

            # attributes that may be useful to have but not required
            'optional_attributes': ['givenName', 'sn'],

            # in this section the list of IdPs we talk to are defined
            },
        },

    # where the remote metadata is stored
    'metadata': {
        'local': ['/opt/peer/pysaml2/terena.xml']
    },

    # set to 1 to output debugging information
    'debug': 1,

    # certificate
    'key_file': '${KEYDIR}/private/${SP_HOSTNAME}.key',
    'cert_file': '${KEYDIR}/certs/${SP_HOSTNAME}.crt',

    # own metadata settings
    'contact_person': [
        {'given_name': 'Peer',
         'sur_name': 'Admin',
         'company': 'Example',
         'email_address': '${SP_CONTACT}',
         'contact_type': 'technical'},
        ],
    # you can set multilanguage information here
    'organization': {
        'name': [('REFEDS', 'en')],
        'display_name': [('REFEDS', 'en')],
        'url': [('http://refeds.org', 'en')],
        },
    }

DOP_USER_AGENT = 'Mozilla/5.0 (X11; Linux i686; rv:10.0.1) Gecko/20100101 Firefox/10.0.1'

PEER_THEME = {
    'LINK_COLOR': '#5669CE',
    'LINK_HOVER': '#1631BC',
    'HEADING_COLOR': '#1631BC',
    'INDEX_HEADING_COLOR': '#ff7b33',
    'HEADER_BACKGROUND': '',
    'CONTENT_BACKGROUND': '',
    'FOOTER_BACKGROUND': '',
    'HOME_TITLE': 'PEER',
    'HOME_SUBTITLE': 'Metadata Registry',
    'JQUERY_UI_THEME': 'default-theme',
}

USER_REGISTER_TERMS_OF_USE = '/opt/peer/user_register_terms_of_use.txt'
METADATA_IMPORT_TERMS_OF_USE = '/opt/peer/metadata_import_terms_of_use.txt'
EOF
fi

mkdir -p /var/log/apache2
mkdir -p /opt/peer/vf_repo

case "$*" in 
   start)
      a2ensite default
      a2ensite default-ssl

      service apache2 start
      tail -f /var/log/apache2/error.log
   ;;
   upgrade|syncdb|migrate)
      . /var/www/peer/bin/activate
      django-admin.py syncdb --settings=peer.settings --migrate --noinput
      django-admin.py migrate --settings=peer.settings --all --noinput
      django-admin.py collectstatic --settings=peer.settings --noinput
   ;;
esac
