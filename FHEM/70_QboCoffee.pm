################################################################
#
#  Copyright notice
#
#  (c) 2017 Fabian Hainz
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################
# $Id:$
################################################################

package main;
use strict;
use warnings;
use JSON;
use Time::Piece;

################################################################

sub QboCoffee_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = "QboCoffee_Define";
  $hash->{GetFn}     = "QboCoffee_Get";
  $hash->{AttrFn}    = "QboCoffee_Attr";
  #$hash->{NotifyFn} = "QboCoffee_Notify";
  $hash->{AttrList}  = "countCoffees:0,1 ".
                       "disable:0,1 ".
                       "interval ".
                       $readingFnAttributes;
}

sub QboCoffee_Define($$) {
  my ($hash, $def) = @_;
  
  my @param = split( "[ \t][ \t]*", $def );
  return "Usage: define <name> QboCoffee <IP>" if ( @param != 3 );
  
  $hash->{NAME} = $param[0];
  $hash->{IP} = $param[2];
  $hash->{INTERVAL} = AttrVal($hash->{NAME}, "interval", 3600);
  $hash->{helper}{qloudAPIURL} = "https://qloud.qbo.coffee";
  
  $hash->{helper}{qboAPI} = {
      latestFirmware => {
          apiURL  => $hash->{helper}{qloudAPIURL}."/firmware/latest",
          method  => "GET",
          rPrefix => "Latest"
      },
      maintenance => {
          apiURL  => "https://".$hash->{IP}."/status/maintenance",
          method  => "GET",
          rPrefix => ""
      },
      machineInfo => {
          apiURL  => "https://".$hash->{IP}."/machineInfo",
          method  => "GET",
          rPrefix => ""
      },
      name        => {
          apiURL  => "https://".$hash->{IP}."/settings/name",
          method  => "GET",
          rPrefix => ""
      },
      settings    => {
          apiURL  => "https://".$hash->{IP}."/settings",
          method  => "GET",
          rPrefix => ""
      }
  };
  
  
  
  # Tag des Jahres speichern für Reset bei wechsel
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $hash->{helper}{yday} = $yday;
  
  # Disabled
  return undef if( IsDisabled($hash->{NAME}) );
    
  readingsSingleUpdate($hash, "state", "Initialized", 1) ;

  InternalTimer( gettimeofday() + 0, "QboCoffee_run", $hash, 0);
  
  return undef;
}

sub QboCoffee_Get($@) {
  my ($hash, @param) = @_;
  my $name = $hash->{NAME}; 
  
  # Disabled
  return undef if( IsDisabled($name) );

  return "get needs at least one argument" if(@param < 2);
  
  my $cmd  = $param[1];
  my $value = $param[2];
  my $list = undef;
  
  $list .= " updateAll:noArg";
  $list .= " machineInfo:noArg";
  $list .= " maintenance:noArg";
  $list .= " name:noArg";
  $list .= " settings:noArg";
  $list .= " versionLatest:noArg";
  
  if( $cmd eq "updateAll" ){
    QboCoffee_getUpdateAll($hash);
  }
  elsif( $cmd eq "machineInfo" ){
    QboCoffee_getMachineInfo($hash);
  }
  elsif( $cmd eq "maintenance" ){
    QboCoffee_getMaintenance($hash);
  }
  elsif( $cmd eq "name" ){
    QboCoffee_getName($hash);
  }
  elsif( $cmd eq "settings" ){
    QboCoffee_getSettings($hash);
  }
  elsif( $cmd eq "versionLatest" ){
    QboCoffee_getLatestFirmwareVersion($hash);
  }
  else{
    return "Unknown argument $cmd, choose one of $list";
  }
}

sub QboCoffee_Attr(@) {
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash = $defs{$name};
  
  if( $cmd eq "set") {
     
    if( $attr_name eq "interval" ){
      $attr_value = 30 if( $attr_value < 30 );
      $hash->{INTERVAL} = $attr_value;
      
      # Disabled
      return undef if( IsDisabled($hash->{NAME}) );
      
      RemoveInternalTimer($hash, "QboCoffee_run");
      InternalTimer( gettimeofday() + $hash->{INTERVAL}, "QboCoffee_run", $hash);
    }
  }
  elsif( $cmd eq "del" ){
  }
  return undef;
}

################################################################

sub QboCoffee_run($) {
  my ($hash) = @_;
  RemoveInternalTimer($hash, "QboCoffee_run");
  InternalTimer( gettimeofday() + $hash->{INTERVAL}, "QboCoffee_run", $hash);
  
  return if( !$init_done );
  
  QboCoffee_coffeeCntRst($hash);
  QboCoffee_getUpdateAll($hash);
}

sub QboCoffee_getUpdateAll($) {
  my ($hash) = @_;

  $hash->{helper}{queue}{maintenance} = 0;
  $hash->{helper}{queue}{machineInfo} = 0;
  $hash->{helper}{queue}{settings} = 0;
  $hash->{helper}{queue}{latestFirmware} = 0;
  $hash->{helper}{queue}{name} = 0;
  
  QboCoffee_getUpdateAll2($hash);
  
}

sub QboCoffee_getUpdateAll2($) {
  my ($hash) = @_;
  
  return if( !$hash->{helper}{queue} );
  
  if( $hash->{helper}{queue}{maintenance} == 0 ) {
    $hash->{helper}{queue}{maintenance} = 1;
    $hash->{helper}{queue}{currentGet} = "maintenance";
    QboCoffee_getMaintenance($hash);
  }
  elsif( $hash->{helper}{queue}{latestFirmware} == 0 ) {
    $hash->{helper}{queue}{latestFirmware} = 1;
    $hash->{helper}{queue}{currentGet} = "latestFirmware";
    QboCoffee_getLatestFirmwareVersion($hash);
  }
  elsif( $hash->{helper}{queue}{machineInfo} == 0 ) {
    $hash->{helper}{queue}{machineInfo} = 1;
    $hash->{helper}{queue}{currentGet} = "machineInfo";
    QboCoffee_getMachineInfo($hash);
  }
  elsif( $hash->{helper}{queue}{settings} == 0 ) {
    $hash->{helper}{queue}{settings} = 1;
    $hash->{helper}{queue}{currentGet} = "settings";
    QboCoffee_getSettings($hash);
  }
  elsif( $hash->{helper}{queue}{name} == 0 ) {
    $hash->{helper}{queue}{name} = 1;
    $hash->{helper}{queue}{currentGet} = "name";
    QboCoffee_getName($hash);
  }

}

################################################################

sub QboCoffee_getMachineInfo($) {
  my ($hash) = @_;
  my $url = $hash->{helper}{qboAPI}{machineInfo}{apiURL};
  my $method = $hash->{helper}{qboAPI}{machineInfo}{method};
  my $rPrefix = $hash->{helper}{qboAPI}{machineInfo}{rPrefix};
  readingsSingleUpdate($hash, "activity", "getMachineInfo", 1);
  QboCoffee_getDataFromMachine($hash, $url, $method, $rPrefix);
}

sub QboCoffee_getLatestFirmwareVersion($) {
  my ($hash) = @_;
  my $url = $hash->{helper}{qboAPI}{latestFirmware}{apiURL};
  my $method = $hash->{helper}{qboAPI}{latestFirmware}{method};
  my $rPrefix = $hash->{helper}{qboAPI}{latestFirmware}{rPrefix};
  readingsSingleUpdate($hash, "activity", "getLatestFirmware", 1);
  QboCoffee_getDataFromMachine($hash, $url, $method, $rPrefix);
}

sub QboCoffee_getMaintenance($) {
  my ($hash) = @_;
  my $url = $hash->{helper}{qboAPI}{maintenance}{apiURL};
  my $method = $hash->{helper}{qboAPI}{maintenance}{method};
  my $rPrefix = $hash->{helper}{qboAPI}{maintenance}{rPrefix};
  readingsSingleUpdate($hash, "activity", "getMaintenance", 1);
  QboCoffee_getDataFromMachine($hash, $url, $method, $rPrefix);
}

sub QboCoffee_getName($) {
  my ($hash) = @_;
  my $url = $hash->{helper}{qboAPI}{name}{apiURL};
  my $method = $hash->{helper}{qboAPI}{name}{method};
  my $rPrefix = $hash->{helper}{qboAPI}{name}{rPrefix};
  readingsSingleUpdate($hash, "activity", "getName", 1);
  QboCoffee_getDataFromMachine($hash, $url, $method, $rPrefix);
}

sub QboCoffee_getSettings($) {
  my ($hash) = @_;
  my $url = $hash->{helper}{qboAPI}{settings}{apiURL};
  my $method = $hash->{helper}{qboAPI}{settings}{method};
  my $rPrefix = $hash->{helper}{qboAPI}{settings}{rPrefix};
  readingsSingleUpdate($hash, "activity", "getSettings", 1);
  QboCoffee_getDataFromMachine($hash, $url, $method, $rPrefix);
}

################################################################

sub QboCoffee_getDataFromMachine($$$;$) {
  my ($hash, $url, $method, $readingsPrefix) = @_;
  
  $hash->{helper}{readingPrefix} = $readingsPrefix;
  
  my $param = {
      url      => $url,
      httpversion => "1.1",
      sslargs => { verify_hostname => 0, SSL_verify_mode => 0 },
      header => { "Content-Type" => "application/json" },
      method   => $method,
      timeout  => 5,
      noshutdown => 1,
      hash     => $hash,
      callback =>  \&QboCoffee_httpResponse
    };
    
    Log3 $hash, 4, $hash->{NAME}.": Try to connect to Qbo Machine. URL: $url";
    
    HttpUtils_NonblockingGet($param);
}

sub QboCoffee_httpResponse($){
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  
  my $readingsPrefix = $hash->{helper}{readingPrefix};
  delete $hash->{helper}{readingPrefix};
  
  if( $err ne "" ) {
    Log3 $name, 3, "QboCoffee: Error while connecting to $hash->{IP}.";
    Log3 $name, 3, "QboCoffee: Error: $err";
  }
  
  elsif( $data ne "" ) {

    my $content = decode_json($data);
    
    # ----------------------------------------------------------------------- #
    # Berechnungen die, Aufgrund Vorher/Nacher Vergleiche, vor dem Readings
    # Updaten stattfinden müssen.
    # ----------------------------------------------------------------------- #
    
    # Kafee Zähler
    if( defined($content->{currentCleanValue}) && AttrVal($name, "countCoffees", 1) == 1 ) {
      QboCoffee_coffeeCnt($hash, $content);
    }
    
    # Kaffee's bis zur nächsten Reinigung
    if( defined($content->{currentCleanValue}) ) {
      my $mCV = ReadingsNum($name, "maximumCleanValue", 0);
      my $cCV = ReadingsNum($name, "currentCleanValue", 0);
      my $cTC = $mCV - $cCV;
      readingsSingleUpdate($hash, "coffeesTillCleaning", $cTC, 1);
    }
    
    
    if( defined($content->{currentDescaleValue}) ) {
      
      my $mDV = ReadingsNum($name, "maximumDescaleValue", 0);
      my $cDV = ReadingsNum($name, "currentDescaleValue", 0);
      my $wC = ReadingsNum($name, "waterCount", 0);
      
      # Wasser Zähler
      my $delta = $content->{currentDescaleValue} - $cDV;
      $wC = $wC + $delta if( $delta > 0 );
      
      # Wasser bis zur nächsten Entkalkung
      my $wTD = $mDV - $cDV;
     
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "waterCount", $wC);
      readingsBulkUpdate($hash, "waterTillDescale", $wTD);
      readingsEndUpdate($hash, 1);
    }
    
    # ----------------------------------------------------------------------- #
    # Readings Updaten
    # ----------------------------------------------------------------------- #
    readingsBeginUpdate($hash);  
    toReadings($hash, $content, "", $readingsPrefix);
    readingsEndUpdate($hash, 1);
    
    
    # ----------------------------------------------------------------------- #
    # Berechnungen die nach dem Readings Updaten stattfinden müssen.
    # ----------------------------------------------------------------------- #
     
    # Latest Firmware
    my $versionUpToDate = 0;
    if( $content->{version} && $content->{version} ne "" && $readingsPrefix eq "Latest") {
      if( ReadingsVal($name, "version", "-") eq $content->{version} ) {
        $versionUpToDate = 1;
      }
      readingsSingleUpdate($hash, "versionUpToDate", $versionUpToDate, 1);
    }
    
    
    if( $hash->{helper}{queue} ) {
      
      readingsSingleUpdate($hash, "activity", "done", 1);
      QboCoffee_getUpdateAll2($hash);
      
    }
    
  }
  
}

################################################################

sub QboCoffee_coffeeCnt($$) {
  my ($hash, $content) = @_;
  
  my $name = $hash->{NAME};
  my $ccv = ReadingsNum($name, "currentCleanValue", 0);
  my $coffeeCnt = ReadingsNum($name, "coffeeCount", 0);
  my $coffeeCntTd = ReadingsNum($name, "coffeeCountToday", 0);
  my $coffeeCntWk = ReadingsNum($name, "coffeeCountWeek", 0);
  my $coffeeCntMo = ReadingsNum($name, "coffeeCountMonth", 0);
  my $coffeeCntYr = ReadingsNum($name, "coffeeCountYear", 0);
  
  # Zählen wenn empfangene CleanValue ungleich der letzten CleanValue ist
  # Value kann durch reset nach der Reinigung auch 0 sein
  if( $content->{currentCleanValue} != $ccv && $content->{currentCleanValue} != 0  ) {
    $coffeeCnt++;
    $coffeeCntTd++;
    $coffeeCntWk++;
    $coffeeCntMo++;
    $coffeeCntYr++;
  }
  
  readingsBeginUpdate($hash); 
  readingsBulkUpdate($hash, "coffeeCount", $coffeeCnt);
  readingsBulkUpdate($hash, "coffeeCountToday", $coffeeCntTd);
  readingsBulkUpdate($hash, "coffeeCountWeek", $coffeeCntWk);
  readingsBulkUpdate($hash, "coffeeCountMonth", $coffeeCntMo);
  readingsBulkUpdate($hash, "coffeeCountYear", $coffeeCntYr);
  readingsEndUpdate($hash, 1);
}

sub QboCoffee_coffeeCntRst($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
   
  my $coffee = 0;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  return if( $hash->{helper}{yday} == $yday );
 
  # Tag gewechselt.
  # Entsprechende Statistiken zurücksetzen  
  
  $hash->{helper}{yday} = $yday;
  
  readingsBeginUpdate($hash);
  
  # Heute
  $coffee = ReadingsNum($name, "coffeeCountToday", 0);
  readingsBulkUpdate($hash,"coffeeCountYesterday", $coffee);
  readingsBulkUpdate($hash,"coffeeCountToday", 0);
  
  # Woche
  if( $wday == 1 ) {
    $coffee = ReadingsNum($name, "coffeeCountWeek", "0");
    readingsBulkUpdate($hash, "coffeeCountWeekLast", $coffee);
    readingsBulkUpdate($hash, "coffeeCountWeek", "0");
  }
  
  # Monat
  if( $mday == 1 ) {
    $coffee = ReadingsNum($name, "coffeeCountMonth", "0");
    readingsBulkUpdate($hash, "coffeeCountMonthLast", $coffee);
    readingsBulkUpdate($hash, "coffeeCountMonth", "0");
  }
  
  # Jahr
  if( $yday == 0 ) {
    $coffee = ReadingsNum($name, "coffeeCountYear", "0");
    readingsBulkUpdate($hash, "coffeeCountYearLast", $coffee);
    readingsBulkUpdate($hash, "coffeeCountYear", "0");
  }
  
  readingsEndUpdate($hash, 1);
}

################################################################

sub toReadings($$;$$) {
  my ($hash,$ref,$prefix,$suffix) = @_;                                               
  $prefix = "" if( !$prefix );                                                  
  $suffix = "" if( !$suffix );                                                  
  $suffix = "$suffix" if( $suffix );                                           
                                                                                
  if(  ref($ref) eq "ARRAY" ) {                                                 
    while( my ($key,$value) = each %{$ref}) {                                      
      toReadings($hash,$value,$prefix.sprintf("%02i",$key+1)."_");                        
    }                                                                           
  } elsif( ref($ref) eq "HASH" ) {                                              
    while( my ($key,$value) = each %{$ref} ) {                                      
      if( ref($value) ) {                                                       
        toReadings($hash,$value,$prefix.$key.$suffix."_");                            
      } else {
          readingsBulkUpdate($hash, $prefix.$key.$suffix, $value);
      }                                                                         
    }                                                                           
  }                                                                             
}      

################################################################                      
                                                                                
1;

=pod
=item summary    Reads several data from a Qbo coffee machine
=item summary_DE Liest diverse Daten einer Qbo Kaffee Maschine aus
=begin html

<a name="QboCoffee"></a>
<h3>QboCoffee</h3>
<ul>
  Short Description
  <br>
  <br>
  <a name="QboCoffee_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; QboCoffee &lt;IP-Adress&gt;</code><br>
    <br>

    Note:<br>
    <ul>
      <li>JSON has to be installed on the FHEM host.</li>
    </ul>
  </ul>
  <br>
    
   <a name="QboCoffee_Get"></a>
    <b>Get</b>
    <ul>
      <li><code>machineInfo</code><br>
        reads machine informations</li>
    </ul><br>
    <ul>
      <li><code>maintenance</code><br>
        reads maintenance informations</li>
    </ul><br>
    <ul>
      <li><code>name</code><br>
        reads the name of the machine</li>
    </ul><br>
    <ul>
      <li><code>updateAll</code><br>
        reads all informations</li>
    </ul><br>
    <ul>
      <li><code>versionLatest</code><br>
        reads the latest firmware version from qbo</li>
    </ul><br>

  <a name="QboCoffee_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>countCoffees<br>
      coffee counting on/off</li>
    <li>interval<br>
      interval to read from qbo machine</li>
   </ul>
</ul>

=end html

=begin html_DE

<a name="QboCoffee"></a>
<h3>QboCoffee</h3>
<ul>
  Mit diesem Modul ist es möglich diverse Information einer <a target="_blank" href="http://qbo.coffee">Qbo</a> Kaffemaschine auszulesen.<br>
  <br><br>
  <a name="QboCoffee_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; QboCoffee &lt;IP-Adress&gt;</code><br>
    <br>

    Notiz:<br>
    JSON muss auf dem FHEM Host installiert sein.<br><br>
  </ul><br>
    
  <a name="QboCoffee_Get"></a>
    <b>Get</b>
    <ul>
      <li><code>machineInfo</code><br>
        Liest Maschinen Informationen aus</li>
    </ul><br>
    <ul>
      <li><code>maintenance</code><br>
        Liest Wartungs Informationen aus</li>
    </ul><br>
    <ul>
      <li><code>name</code><br>
        Liest den Namen der Maschine aus</li>
    </ul><br>
    <ul>
      <li><code>updateAll</code><br>
        Liest alle Informationen aus der Maschine aus</li>
    </ul><br>
    <ul>
      <li><code>versionLatest</code><br>
        Liest die aktuelle Firmware Version von Qbo aus</li>
    </ul><br>

  <a name="QboCoffee_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li><code>countCoffees</code><br>
      Kaffe Zählung Ein/Aus</li>
    <li><code>interval</code><br>
      Intervall nachdem alle Readings aktualisiert werden</li>
  </ul><br>
</ul>

=end html_DE

=cut