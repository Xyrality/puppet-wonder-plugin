class wonder (
  $username = 'wouser',
  $userid = 2000,
  $groupname = 'wouser',
  $groupid = 2000,
  ) {

  group { $groupname:
    ensure => present,
    gid    => "${groupid}",
  }

  user { $username:
    ensure     => present,
    uid        => "${userid}",
    gid        => "${groupid}",
    shell      => '/bin/bash',
    managehome => false,
  }

  file { "/home/${username}":
    ensure  => directory,
    recurse => true,
    owner   => "${userid}",
    group   => "${groupid}",
  }
  
  if !defined(Package['wget']) {
    package { 'wget':
        ensure => present,
        name   => 'wget'
    }
  }
  
  if !defined(Package['curl']) {
    package { 'curl':
        ensure => present,
        name   => 'curl'
    }
  }

  if $osfamily == 'debian' {

    file { '/etc/apt/apt.conf.d/99auth':
      owner     => root,
      group     => root,
      content   => 'APT::Get::AllowUnauthenticated yes;',
      mode      => 644,
    }

    apt::source { 'wocommunity':
      comment           => 'WOCommunity apt mirror',
      location          => 'http://packages.wocommunity.org/ubuntu',
      release           => 'trusty',
      repos             => 'main',
      include_deb       => true,
      key               => '1D2A5E5AA13158380229B94925C7D0023AAD08A4',
      key_source        => 'http://packages.wocommunity.org/ubuntu/signature.gpg',
      require           => File['/etc/apt/apt.conf.d/99auth'],
    }

    file { '/var/cache/debconf/webobjects.preseed':
        ensure => present,
        require => [User[$username], Group[$groupname]],
        content => "webobjects  webobjects/local_wo_dmg boolean false
  webobjects  webobjects/groupname  string  ${groupname}
  webobjects  webobjects/local_wo_dmg_base_url  string
  webobjects  webobjects/local_wo_dmg_base_url_not_supported  note
  webobjects  webobjects/username string  ${username}
  "
    }

    file { '/etc/default/webobjects':
      ensure => present,
      content => "WEBOBJECTS_GROUP=${groupname}
  WEBOBJECTS_USER=${username}
  NEXT_ROOT=/usr/share/webobjects
  JAVA_MONITOR_ARGS=\"-WOPort 1086\"
  WEBOBJECTS_URL=
  "
    }

    file { '/etc/apache2/mods-available/webobjects.conf':
      ensure => present,
      source => 'puppet:///modules/wonder/apache-mod-webobjects.conf',
      require => Package['httpd']
    }

    package { 'webobjects': 
      ensure  => present,
      responsefile => '/var/cache/debconf/webobjects.preseed',
      require => [File['/var/cache/debconf/webobjects.preseed'], File['/etc/default/webobjects'], Apt::Source['wocommunity']],
    }

    package { 'libapache2-mod-wo':
      ensure => present,
      require => [Package['webobjects'], Package['httpd'], File['/etc/apache2/mods-available/webobjects.conf']],
      notify => Service['httpd'],
    }
    
    package { 'projectwonder-javamonitor':
      ensure => present,
      require => Package['webobjects'],
    }

    package { 'projectwonder-wotaskd':
      ensure => present,
      require => Package['webobjects'],
    }

  } elsif $osfamily == 'redhat' {

    yumrepo { "wocommunity":
      baseurl => "http://packages.wocommunity.org/CentOS/$operatingsystemrelease/$architecture",
      descr => "WOCommunity repository",
      enabled => 1,
      gpgcheck => 0
    }
   
    package { 'projectwonder-javamonitor':
      ensure => present,
      name   => 'womonitor'
    }

    package { 'projectwonder-wotaskd':
      ensure => present,
      name   => 'wotaskd'
    }
    
    package { 'libapache2-mod-wo':
      ensure  => present,
      name    => 'woadaptor',
      require => Package['httpd'],
      notify  => Service['httpd'],
    }

  }

  exec { 'wait for monitor':
    require => Package['projectwonder-javamonitor', 'wget'],
    command => '/usr/bin/wget --spider --tries 10 --retry-connrefused http://localhost:1086/'
  }

  exec { 'add localhost to monitor':
    require => Exec['wait for monitor'],
    command => "/usr/bin/curl -X POST -d \"{id: 'localhost',type: 'MHost', osType: 'UNIX', address: '127.0.0.1', name: 'localhost'}\" http://localhost:1086/cgi-bin/WebObjects/JavaMonitor.woa/ra/mHosts.json"
  }

  exec { 'set WO adaptor URL':
    require => [ Exec['wait for monitor'], Package['curl'] ],
    command => "/usr/bin/curl -X PUT -d \"{woAdaptor:'http://localhost:8080/cgi-bin/WebObjects'}\" http://localhost:1086/cgi-bin/WebObjects/JavaMonitor.woa/ra/mSiteConfig.json"
  }

}
