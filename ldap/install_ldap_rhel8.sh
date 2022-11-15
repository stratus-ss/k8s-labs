sudo dnf install wget vim cyrus-sasl-devel libtool-ltdl-devel openssl-devel libdb-devel make libtool autoconf  tar gcc perl perl-devel -y
sudo useradd -r -M -d /var/lib/openldap -u 55 -s /usr/sbin/nologin ldap

VER=2.6.3
wget https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-$VER.tgz

tar xzf openldap-$VER.tgz
sudo mv openldap-$VER /opt
cd /opt/openldap-$VER
sudo dnf groupinstall "Development Tools" -y

./configure --prefix=/usr --sysconfdir=/etc \
--enable-debug --with-tls=openssl --with-cyrus-sasl --enable-dynamic \
--enable-crypt --enable-spasswd --enable-slapd --enable-modules \
--enable-rlookups
sudo make depend
sudo make
sudo make install
sudo mkdir /var/lib/openldap /etc/openldap/slapd.d

sudo chown -R ldap:ldap /var/lib/openldap
sudo chown root:ldap /etc/openldap/slapd.conf
sudo chmod 640 /etc/openldap/slapd.conf

sudo cp /usr/share/doc/sudo/schema.OpenLDAP  /etc/openldap/schema/sudo.schema

cat << 'EOL' > /etc/openldap/schema/sudo.ldif
dn: cn=sudo,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: sudo
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.1 NAME 'sudoUser' DESC 'User(s) who may  run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.2 NAME 'sudoHost' DESC 'Host(s) who may run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.3 NAME 'sudoCommand' DESC 'Command(s) to be executed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.4 NAME 'sudoRunAs' DESC 'User(s) impersonated by sudo (deprecated)' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.5 NAME 'sudoOption' DESC 'Options(s) followed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.6 NAME 'sudoRunAsUser' DESC 'User(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.7 NAME 'sudoRunAsGroup' DESC 'Group(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcObjectClasses: ( 1.3.6.1.4.1.15953.9.2.1 NAME 'sudoRole' SUP top STRUCTURAL DESC 'Sudoer Entries' MUST ( cn ) MAY ( sudoUser $ sudoHost $ sudoCommand $ sudoRunAs $ sudoRunAsUser $ sudoRunAsGroup $ sudoOption $ description ) )
EOL


sudo mv /etc/openldap/slapd.ldif /etc/openldap/slapd.ldif.bak

cat << 'EOL' > /etc/openldap/slapd.ldif
dn: cn=config
objectClass: olcGlobal
cn: config
olcArgsFile: /var/lib/openldap/slapd.args
olcPidFile: /var/lib/openldap/slapd.pid

dn: cn=schema,cn=config
objectClass: olcSchemaConfig
cn: schema

dn: cn=module,cn=config
objectClass: olcModuleList
cn: module
olcModulepath: /usr/libexec/openldap
olcModuleload: back_mdb.la

# Include more schemas in addition to default core
include: file:///etc/openldap/schema/core.ldif
include: file:///etc/openldap/schema/cosine.ldif
include: file:///etc/openldap/schema/nis.ldif
include: file:///etc/openldap/schema/inetorgperson.ldif
include: file:///etc/openldap/schema/sudo.ldif

dn: olcDatabase=frontend,cn=config
objectClass: olcDatabaseConfig
objectClass: olcFrontendConfig
olcDatabase: frontend
olcAccess: to dn.base="cn=Subschema" by * read
olcAccess: to *
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none

dn: olcDatabase=config,cn=config
objectClass: olcDatabaseConfig
olcDatabase: config
olcRootDN: cn=config
olcAccess: to *
  by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none

EOL

sudo slapadd -n 0 -F /etc/openldap/slapd.d -l /etc/openldap/slapd.ldif

sudo chown -R ldap:ldap /etc/openldap/slapd.d

cat << 'EOL' > /etc/systemd/system/slapd.service
[Unit]
Description=OpenLDAP Server Daemon
After=syslog.target network-online.target
Documentation=man:slapd
Documentation=man:slapd-mdb

[Service]
Type=forking
PIDFile=/var/lib/openldap/slapd.pid
Environment="SLAPD_URLS=ldap:/// ldapi:/// ldaps:///"
Environment="SLAPD_OPTIONS=-F /etc/openldap/slapd.d"
ExecStart=/usr/libexec/slapd -u ldap -g ldap -h ${SLAPD_URLS} $SLAPD_OPTIONS

[Install]
WantedBy=multi-user.target

EOL

sudo systemctl daemon-reload
sudo systemctl enable --now slapd

cat << 'EOL' > rootdn.ldif

dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbMaxSize: 42949672960
olcDbDirectory: /var/lib/openldap
olcSuffix: dc=rhel8-k8s,dc=k3s,dc=lab
olcRootDN: cn=admin,dc=rhel8-k8s,dc=k3s,dc=lab
olcRootPW: {SSHA}IvEh5wvDlkxFE2N7+TaRzdg8fm7HwqZY
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn pres,eq,approx,sub
olcDbIndex: mail pres,eq,sub
olcDbIndex: objectClass pres,eq
olcDbIndex: loginShell pres,eq
olcDbIndex: sudoUser,sudoHost pres,eq
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.subtree="ou=system,dc=rhel8-k8s,dc=k3s,dc=lab" read
  by * none
olcAccess: to dn.subtree="ou=system,dc=rhel8-k8s,dc=k3s,dc=lab" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
olcAccess: to dn.subtree="dc=rhel8-k8s,dc=k3s,dc=lab" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read
  by * none

EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f rootdn.ldif

cat << 'EOL' > basedn.ldif

dn: dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: dcObject
objectClass: organization
objectClass: top
o: k3s
dc: rhel8-k8s

dn: ou=groups,dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: organizationalUnit
objectClass: top
ou: groups

dn: ou=people,dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: organizationalUnit
objectClass: top
ou: people

EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f basedn.ldif

cat << 'EOL' > users.ldif

dn: uid=user1,ou=people,dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: user1
cn: Test
sn: User1
loginShell: /bin/bash
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/user1
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: 0

dn: cn=user1,ou=groups,dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: posixGroup
cn: user1
gidNumber: 10000
memberUid: user1

EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f users.ldif

ldappasswd -H ldapi:/// -Y EXTERNAL "uid=user1,ou=people,dc=rhel8-k8s,dc=k3s,dc=lab" -s passw0rd1

cat << 'EOL' > bindDNuser.ldif

dn: ou=system,dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: organizationalUnit
objectClass: top
ou: system

dn: cn=readonly,ou=system,dc=rhel8-k8s,dc=k3s,dc=lab
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
userPassword: {SSHA}/DCIjMrorpeQMdvbyuAzkryUjm2ijRDN
description: Bind DN user for LDAP Operations

EOL

sudo ldapadd -Y EXTERNAL -H ldapi:/// -f bindDNuser.ldif

sudo firewall-cmd --add-service={ldap,ldaps} --permanent
sudo firewall-cmd --reload

ldapsearch -x -D "cn=readonly,ou=system,dc=rhel8-k8s,dc=k3s,dc=lab" -w bindpassw0rd -b 'ou=groups,dc=rhel8-k8s,dc=k3s,dc=lab'
