#!/usr/bin/env ruby
# Handler Sensu
# Fonction : Ajoute, si n?cessaire, une ligne au format attendu par l'agent ITM de SNCF pour alerte au PAD
# Entr?e: Json de l'?v?nement compl?t? par le mutator
# Sortie: mise ? jour du fichier tivoli.log
# Auteur : S.Boulinguez - 05/02/2015 
########################################################################################################

require 'rubygems'
require 'json'
require 'net/http'
require 'sensu-handler'

class Tivoli < Sensu::Handler


def handle
# Initialisation de variables utiles
serveur_sensu=`hostname`.strip
journal = File.open('/tmp/handler_journal.txt','a')
tivoli = File.open('/tmp/tivoli.log','a')
date = Time.new()
home_script="/etc/sensu/nagios"
home_cfg="#{home_script}/CFG"
commentaire = "Evenement Sensu VSCT"
source="SENSU"
return_code=0

# On lit le d?tail de l'?v?nement
# Un petit appel toolbox en bonus pour tenter d'avoir le nom complet de l'appli
check = @event['check']
client_name = @event['client']['name'].upcase
service = check['name']
state = check['status']
trigramme= @event['appli']
platef= "#{trigramme}#{@event['env']}"

#Trace dans le journal syst?matique pour aider ? l'analyse
whichscript=File.basename($0)
# journal.write("\n#{date}\n#{whichscript} parsing...\n")
# journal.write("Hostname: #{client_name}\n")
# journal.write("Service: #{service}\n")
# journal.write("State: #{state}\n")

# On commence par v?rifier l'?tat du service
# Si l'?tat est ? OK -> on sort
#Sous Sensu, ce cas ne doit jamais arriv? car un OK est un non ?v?nement
if state == 0
  # journal.write("Service OK, sortie de #{whichscript}\n")
  # journal.close
  exit #{state}
# Si l'?tat n'est pas CRITICAL -> on n'alerte pas le PAD
# Cas d?j? g?r? par les scripts de notification par mail
elsif state != 2
  # journal.write("Alerte non critique, sortie de #{whichscript}\n")
  # journal.close
  exit #{state}
end

#Trace dans le journal uniquement des ?v?nements qui doivent remonter en alerte Tivoli
journal.write("\n#{date}\n#{whichscript} parsing...\n")
journal.write("Hostname: #{client_name}\n")
journal.write("Service: #{service}\n")
journal.write("State: #{state}\n")
# journal.write(event.to_json)

#Est-ce que ce check est mis en silence? (stash silence)
stashes = [
        ['client', '/silence/' + @event['client']['name']],
        ['check', '/silence/' + @event['client']['name'] + '/' + service],
        ['check', '/silence/all/' + service ]
      ]
stashes.each do |(scope, path)|
  begin
    timeout(2) do
    if stash_exists?(path)
      journal.write("#{scope} en mode maintenance\nAucune alerte\n")
      exit 0
    end
    end
  rescue Timeout::Error
    journal.write('timed out while attempting to query the sensu api for a stash') && journal.close
    puts 'timed out while attempting to query the sensu api for a stash'
  end
end


#R?cup?ration du nom complet de l'appli dans le Env via appel Toolbox
appName = "TST"
if appName == "probleme"
  appName = trigramme
end


# Cas particulier keepalive (hearbeat client sensu)
if service == "keepalive"
  tivoli.write("#{client_name}!CRITICAL!#{@event['appli']}!#{appName}!#{source}!#{check['issued']}!VSCI!#{@event['situation']}!#{commentaire}!#{check['output']}\n".squeeze(" ")) && tivoli.close
  journal.write("Outputs: #{outputs}\n") && journal.close
  exit 0
end

# On charge le fichier de configuration des messages TIVOLI correspondant au composant technique
type=@event['type']
#msgErr = "#{serveur_sensu} : Fichier de configuration TIVOLI introuvable pour le composant technique #{type}!" unless !(File.exist?("#{home_cfg}/tivoli_#{type}.cfg")) and journal.write("#{msgErr}\n") and puts msgErr and exit 3
if !(File.exist?("#{home_cfg}/tivoli_#{type}.cfg"))
  msgErr = "#{serveur_sensu} : Fichier de configuration TIVOLI introuvable pour le composant technique #{type}!"
  journal.write("#{msgErr}\n")
    journal.close
  puts msgErr
  exit 3
end

#chaque cl?=valeur est mis en hashtable
messages = { }
tivolicfg=File.open("#{home_cfg}/tivoli_#{type}.cfg",'r')
tivolicfg.each_line do |line|
  label, value = line.encode('iso-8859-15',:invalid => :replace).split("=")
  messages.merge!("#{label.strip}" => "#{value.strip}")
end
tivolicfg.close

# On r?cup?re les param?tres suivants pour le d?tail du service
outputs = check['output'].strip
# if check[:perfdata]
  # perfs = check[:perfdata].strip
# end
error_details=''
details = Hash.new { Hash.new }
if check[:error_details]
  error_details = check[:error_details].strip
  #On les charge dans un hash pour simplifier la suite du traitement
  temp = {}
  error_details.split('#').each do |detail|
      type_err , erreur = detail.split('=',2)
      #erreur = detail.split('=',2).last.strip
      elt_err , detail_err = erreur.split(':',2)
      #detail_err = erreur.split(':',2).last.strip
      temp[type_err] = detail_err
      details[elt_err] = temp
      temp = {}
  end
end
journal.write("Outputs: #{outputs}\n")
journal.write("Error_details : #{error_details}\n")

currentAttempt = @event['occurrences']
maxAttempt = check['occurrences']

# journal.write("currentAttempt: #{currentAttempt}\n")
# journal.write("maxAttempt : #{maxAttempt}\n")

#ici dans le notify_tivoli nagios on force la notif au PAD du check_nrpe (time out sonde, etc) pour les services Oracle
#=> il faudra voir comment g?rer la notification "heartbeat" de Sensu ici par la suite

pingKoTab={}
errorsTab={}
instancesKO = ""
# Gestion des serveurs Actif / Passif 
if outputs != messages["passif_msg"]
  # On traite la sortie uniquement si le retour est
  # diff?rent de OK et si le nombre d'essais a atteint le
  # nombre max d?fini dans Centreon (gestion persistence)
  if currentAttempt >= maxAttempt
    journal.write("maxAttempt reached !\n")
    # La sortie est d?coup?e en blocs <cl?=valeur>
    # s?par?s par des espaces
    output = outputs.split(' ')
    output.each do |outputelems| 
      # Pour chaque type d'erreur
      outputelem = outputelems.split('=')
      error = outputelem.shift

      # On r?cup?re la liste des instances concern?es (ou autres ?l?ments similaires)
      instancesList = outputelem.shift.split(',')
      
      # Puis on construit 2 listes pour stocker l'?tat de chaque instance
      # errorsTab est de la forme errorsList["VSLROMH11"] = "WARN ERR"
      # pingKoTab est de la forme pingKoList["VSLROMH11"] = "PING"
      # Pour chaque liste, on commence par regarder si des informations sont
      # d?j? stock?es pour l'instance courante. Si non, on cr?? une entr?e
      # pour l'instance. Si oui, on r?cup?re les infos et on ajoute
      instancesList.each do |instance|
        # On conserve le nom de l'instance qui est en erreur pour pouvoir la traiter plus tard
        # Uniquement si elle n'a pas d?j? ?t? stock?e
        if !(pingKoTab["#{instance}"]) && !(errorsTab["#{instance}"])
          if instancesKO != ""
            instancesKO = "#{instancesKO}@#{instance}"
          else
            instancesKO = "#{instance}"
          end
        end
        
        if messages["instance_ko_msg"] && error == messages["instance_ko_msg"]
          if !(pingKoTab["#{instance}"])
            pingKoTab["#{instance}"] = "PING"
          end
        else 
          if errorsTab["#{instance}"]
              errorsList = errorsTab["#{instance}"]
          else
              errorsList = ""
          end
          if errorsList != ""
              errorsList = "#{errorsList} #{error}"
          else
              errorsList = "#{error}"
          end
          errorsTab["#{instance}"] = "#{errorsList}"
        end
      end
    end
  else
    journal.write("maxAttempt not reached yet...\n")
  end
end

#####################
## 
## REMONTEES TIVOLI
##
#####################
alertsTab={}
# Si la liste des instances KO n'est pas vide, on remonte les erreurs
# ? TIVOLI pour chaque instance de cette liste
# Pour cela, on utilise le contenu de pingKoTab et errorsTab
if instancesKO != ""
  #journal.write("instancesKO: #{instancesKO}\n")
  
  instancesList = instancesKO.split('@')
  instances = ""
  # Pour chaque instance de la liste, on sait que l'instance a un probleme mais
  # on ne sait pas exactement lequel
  # Si le fichier de configuration l'indique, on fait un check ? distance pour
  # r?cup?rer l'erreur pr?cise (cas de Weblogic, Tomcat, Tuxedo ...)
  instancesList.each do |instance|
    # On construit la liste des instances KO sur le serveur
    # -> Pour remonter la liste d'instances en une seule alerte
    if pingKoTab["#{instance}"]
          instances = "#{instances} #{instance}"
    end

    # Si l'instance est marqu?e comme contenant des erreurs
    if errorsTab["#{instance}"]
      #puts "instance : #{instance}"
      if !(details["#{instance}"].empty?) && details["#{instance}"].keys != []
        # Cas o? il y a du d?tail en param?tre
        #puts "cles details : #{details["#{instance}"].keys}"
        details["#{instance}"].each_key do |typerr|
          result_err = details["#{instance}"]["#{typerr}"]
          result_err.each_line do |msgElem|
            if messages["#{typerr.downcase}_msg"]
              tivoli.write("#{client_name}!CRITICAL!#{@event['appli']}!#{appName}!#{source}!#{check['issued']}!#{messages["groupe_astreinte"]}!#{@event['situation']}_#{typerr.upcase}!#{commentaire}!#{@event['client_appli']}#{messages["#{typerr.downcase}_msg"]} #{instance}:#{msgElem.strip}\n".squeeze(" "))
            else
              msgErr="ERREUR #{whichscript} sur #{serveur_sensu}: #{typerr.downcase}_msg absent du fichier #{home_cfg}/tivoli_#{type}.cfg pour #{@event['situation']}"
              journal.write("\n#{msgErr}\n")
              puts msgErr
              #On ne sort pas pour traiter les autres alertes mais on pr?viendra ? la fin du script
              return_code=3
            end
          end
        end
      else
        # Cas "classique"
        #puts "errorsTab pour #{instance} : #{errorsTab["#{instance}"]}"
        # On transforme les listes de type errorsTab["VSLROMH11"] = "WARN CRIT" et errorsTab["VSLROMH12"] = "WARN"
        # en alertsTab["WARN"] = "VSLROMH11 , VSLROMH12" et alertsTab["CRIT"] = "VSLROMH11"
        # Ceci permet de remonter les alertes multiples (sans d?tail) en une ligne et
        # de limiter ainsi le nombre global d'alertes remont?es ? Tivoli
        erreursList = errorsTab["#{instance}"].split(' ')
        erreursList.each do |erreurElem|
        #puts "erreurElem : #{erreurElem}"
          if alertsTab["#{erreurElem}"]
            alertsList = alertsTab["#{erreurElem}"]
          else
            alertsList = ""
          end
          if alertsList.empty?
            alertsList = "#{instance}"
          else
            alertsList = "#{alertsList} , #{instance}"
          end
          alertsTab["#{erreurElem}"] = "#{alertsList}"
        end
      end
    end
  end

  # Une fois la liste des instances parcourue pour traiter les erreurs, 
  # on remonte la liste des instances KO en un seul message
  if instances != ""
    tivoli.write("#{client_name}!CRITICAL!#{@event['appli']}!#{appName}!#{source}!#{check['issued']}!#{messages["groupe_astreinte"]}!#{@event['situation']}_PING!#{commentaire}!#{@event['client_appli']}#{messages["pingko_msg"]} #{client_name.upcase} :#{instances}\n".squeeze(" "))
  end

  # De m?me, on remonte en une seule les erreurs qui n'ont pas de d?tail particulier
  alertsTab.each_key do |alertElem|
    erreurElem = "#{alertsTab["#{alertElem}"]}"
    # journal.write("alertElem : #{alertElem}\n")
    if messages["#{alertElem.downcase}_msg"]
      tivoli.write("#{client_name}!CRITICAL!#{@event['appli']}!#{appName}!#{source}!#{check['issued']}!#{messages["groupe_astreinte"]}!#{@event['situation']}_#{alertElem.upcase}!#{commentaire}!#{@event['client_appli']}#{messages["#{alertElem.downcase}_msg"]}#{@event['supplement_message']}:#{erreurElem}\n".squeeze(" "))
    else
      msgErr="ERREUR #{whichscript} sur #{serveur_sensu}: #{alertElem.downcase}_msg absent du fichier #{home_cfg}/tivoli_#{type}.cfg pour #{@event['situation']}"
      journal.write("\n#{msgErr}\n")
      puts msgErr
      #On ne sort pas pour traiter les autres alertes mais on pr?viendra ? la fin du script
      return_code=3
    end
  end
end

#On peut fermer le journal
journal.close

#On peut fermer le log tivoli
tivoli.close

exit return_code

end
end