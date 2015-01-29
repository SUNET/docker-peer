# docker-peer

A docker-image for running https://github.com/Yaco-Sistemas/peer

In order to run this you need postgres. A sample fig (docker compose) fig.yml illustrates the setup needed. 
All user data (except SSL keys that are in /etc/ssl) is in /opt/peer. 

The entrypoint takes two commands: "start" (the default) and "upgrade" (or "syncb") which performs a django 
syncdb+migration+collectstatic. Run 'upgrade' after an upgrade or if the db is empty.
