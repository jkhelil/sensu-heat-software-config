#!/usr/bin/env ruby
# Mutator Sensu
# Fonction : ajouter tous les ?l?ments au json de l'?v?nement n?cessaire ? la notification ? Tivoli/PAD
# Entr?e: Json de l'?v?nement
# Sortie: Json compl?t?
# Auteur : S.Boulinguez - 04/02/2015
########################################################################################################

require 'rubygems'
require 'json'

# Initialisation de variables utiles
serveur_sensu=`hostname`.strip
journal = File.open('/tmp/mutator_journal.txt','a')
date = Time.new()

# On lit le d?tail de l'?v?nement
event = JSON.parse(STDIN.read, :symbolize_names => true)
check  = event[:check]
client_name  = event[:client][:name]
service = check[:name]
state = check[:status]
# Perfdata au format Nagios?
# On divise le output en 2 ou 3 : 
# output avec juste erreur, et perfdata avec donn?es de perf
# et ?ventuellement error_details pour le d?tail des erreurs (nouveau m?canisme pour erreurs log)
check_output=check[:output]
if check[:output_format] == "nagios_perfdata"
  #Est-ce qu'on a des perfdata?
  if check[:output].include? "|"
    check_output , second_part = check[:output].split('|')
    #Est-ce qu'on a ?galement des d?tails d'erreurs?
    #Chaque d?tail est s?par? par un "#"
    if second_part.include? "#"
      perfdata , error_details = second_part.split('#',2)
    else
      perfdata = check[:output].split('|').last.strip
    end
  #Est-ce qu'on a uniquement des d?tails d'erreurs?   
  #Chaque d?tail est s?par? par un "#"
  elsif check[:output].include? "#"
    check_output , error_details = check[:output].split('#',2)
  end
  if perfdata 
    perfdata.strip
  end
end
event[:check].merge!(:output => check_output, :perfdata => perfdata , :error_details => error_details)

#Trace dans le journal syst?matique pour aider ? l'analyse
whichscript=File.basename($0)
#journal.write("\n#{date}\n#{whichscript} parsing...\n")
#journal.write("Hostname: #{client_name}\n")
#journal.write("Service: #{service}\n")
#journal.write("State: #{state}\n")

# On r?cup?re le code applicatif, l'environnement et le composant technique (? minima) en fonction du service
parametres = service.split('_')
appli = parametres[0]
supplement_message = ''
composant = ''
client_appli = ''
#Est-ce qu'on a un nom de service applicatif (=plusieurs ?l?ments entre _), ou un composant syst?me/transverse? (=nom unique)
if appli != service
  #Cas d'un service applicatif ou sgbd, non syst?me/transverse
  env = parametres[1]
  type = parametres[2]
  
  # Le quatri?me param?tre (composant applicatif) est facultatif
  # Ce qui a un impact sur le nom de la  plateforme et le nom de la situation remont?e dans TIVOLI, sauf si ce param?tre est un m?trique
  if parametres[3] && parametres[3] !~ /Cnx|Items|Mem|Ratio|CPU|Stats|Heap|Threads|Requests|Sessions|QueueSize|ConsumerCount|EnqueueCount|Slave|StoreUsage|watCache|watSessions|Metro|NodeInfo|FSState|JobTrackerInfo|JobTrackerMetrics|DataInfo|TaskTrackerInfo|TaskTrackerMetrics|Status/
    # On a un composant (pas une sonde de metrologie)
    composant = parametres[3]
    #platef = "#{appli}#{env}_#{composant}"
    situation = "#{appli}_#{env}_#{type}_#{composant}"
    #Est-ce qu'on a un client pr?cis? sur le service? (nouveaut? YAML)
    if parametres[4]
      #On a une notion de client
      client_appli=parametres[4]
      #On modifie la platef
      #platef = "#{appli}#{env}-#{client_appli}_#{composant}"
      #Client mis en forme pour l'alerte au PAD
      client_appli="Client #{parametres[4]}: "
    end
  elsif parametres[3]
    # Cas metrologie
    # Avec composant appli ou non?
    if parametres[4]
      composant = parametres[4];
      #Est-ce qu'on a un client pr?cis? sur le service? (possible qu'avec composant car YAML)
      if parametres[5]
        client_appli=parametres[5]
        #platef = "#{appli}#{env}-#{client_appli}_#{composant}"
      # else
        #platef = "#{appli}#{env}_#{composant}"
      end
      situation = "#{appli}_#{env}_#{type}_#{parametres[3]}_#{composant}"
    else
      #platef = "#{appli}#{env}";
      situation = "#{appli}_#{env}_#{type}_#{parametres[3]}"
    end
  else
    # Cas classique
    #platef = "#{appli}#{env}"
    situation = "#{appli}_#{env}_#{type}"
  end
else
  # Cas composant syst?me ou transverse
  appli=appli.upcase
  # D?duction de l'env en fonction du hostname du serveur Nagios/Sensu
  if serveur_sensu =~ /imola|cesa/i
    env="PREP"
  elsif serveur_sensu =~ /grado|dourges/i
    env="PRD" 
  else
    env="UNK"
  end
  
  # Correspondances entre les situations Tivoli et les services Centreon syst?mes ou transverses.
  situations = { "CHARGE" => "YVT" , "CPU" => "YVT" , "RAM" => "YVT" , "SWAP" => "YVT" , "DISK" => "YVT" , "THREADS" => "YVT" , "DNS" => "YVT" , "OSSEC" => "YVT",
  "DRBD" => "YVT" , "MOUNT" => "YVT" , "HARDWARE" => "YVT" , "HEARTBEAT" => "YVT" , "DOLLARU" => "YTL" , "CLUSTER" => "YVT" , "SYSLOG" => "YVT", "SYSLOGMSG" => "YVT", "KEEPALIVED" => "YVT", 
  "MAIL" => "YVT" , "RNVP" => "RNV", "NETWORK" => "YVN", "CRON" => "YVT", "LDAP" => "YVT", "NTP" => "YVT", "ZOMBIES" => "YVT", "IOSTAT" => "YVT", "VMSTAT" => "YVT",
  "RSAENVISION" => "YVT" , "NSCA" => "YVT" , "FREESPACE" => "YVT" , "MEMORY" => "YVT" , "TOTALPROC" => "YVT" , "USERS" => "YVT" , "ZOMBIE" => "YVT" , "DRIVESPACE" => "YVT" , 
  "AUDITDEST" => "YVT" , "DIAGDEST" => "YVT", "DNSCLIENT" => "YVT" , "LANMANSERVER" => "YVT" , "LANMANWORKSTATION" => "YVT" , "NETLOGON" => "YVT", "RPC" => "YVT", "SQUID" => "YVT" ,
  "BRUTEFORCEAFTERSALE" => "YVT", "KEEPALIVE" => "YVT" }
  
  # R?cup?ration de la situation Tivoli si celle-ci a ?t? d?finie
  if situations[appli] 
    type=situations[appli]
    if appli != "KEEPALIVE"
      situation = "#{type}_#{env}_#{appli}"
    else
      situation = "#{type}_#{env}_PING"
    end
    if type == "YVT" && appli != "MOUNT" 
      supplement_message = " #{appli} "
    end
    #Astuce pour que tout apparaisse ensuite comme m?me application
    appli=type
    #On n'a pas de plateforme mais pour les instcheck ?ventuels, on initialise sa valeur => instcheck disparu avec Sensu
    # platef=env
  else
    msgErr="ERREUR #{whichscript} : Situation Tivoli non definie pour #{appli} sur #{client_name}!"
    journal.write("\n#{msgErr}\n")
    journal.close
    puts msgErr
    exit 3
  end
end

#On ajoute tous ces ?l?ments d?duits au JSON d'origine
event.merge!(:env => env, :type => type, :appli => appli , :situation => situation , :client_appli => client_appli , :supplement_message => supplement_message )
#Ainsi qu'au journal, pour aide au debug
#journal.write(event.to_json)
#On peut fermer le journal
journal.close

#on renvoie le json
puts event.to_json