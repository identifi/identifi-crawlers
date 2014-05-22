require 'rubygems'
require 'nokogiri'
require 'net/http'
require 'json'
require 'yaml'
require './identifirpc.rb'

CONFIG = {}
YAML.load_file("./config.yml").each { |k,v| CONFIG["#{k}"] = v }

USER_LIST_FILE = "bitcoin-otc-data/bitcoin-otc-wot.html"
RATINGDETAILS_DIR = "bitcoin-otc-data/ratingdetails"
VIEWGPG_DIR = "bitcoin-otc-data/viewgpg"
LISTING_URI = URI("http://bitcoin-otc.com/viewratings.php")
IDENTIFI_PACKET = {
                    signedData:
                      {
                        timestamp: 0,
                        author: [],
                        recipient: [],
                        rating: 0,
                        maxRating: 10,
                        minRating: -10,
                        comment: "",
                        type: "review"
                      },
                    signature: {}
                  }

def ratingsJsonUrl(nickname)
  "http://bitcoin-otc.com/viewratingdetail.php?nick=#{nickname}&sign=ANY&type=RECV&outformat=json"
end

def userJsonUrl(nickname)
  "http://bitcoin-otc.com/viewgpg.php?nick=#{nickname}&outformat=json"
end

def otcUserID(nickname)
  "#{nickname}@bitcoin-otc.com"
end

def getuserlist
  page = Nokogiri::HTML(open(USER_LIST_FILE))
  userRows = page.css('table.datadisplay tr')
  users = Array.new

  userRows.drop(2).each do |row|
    users.push row.css('td')[1].text
  end

  return users
end

def downloadRatingDetails(http)
  request = Net::HTTP::Get.new ratingsJsonUrl(username)
  response = http.request request # Net::HTTPResponse object

  case response
  when Net::HTTPSuccess then
    out_file = File.new("#{RATINGDETAILS_DIR}/#{username}.json", "w")
    out_file.puts(response.body)
    out_file.close
  else
    puts response.value
  end
end

def downloadViewGPG(http)
  request = Net::HTTP::Get.new userJsonUrl(username)
  response = http.request request # Net::HTTPResponse object

  case response
  when Net::HTTPSuccess then
    out_file = File.new("#{VIEWGPG_DIR}/#{username}.json", "w")
    out_file.puts(response.body)
    out_file.close
  else
    puts response.value
  end
end

def download
	Net::HTTP.start(LISTING_URI.host, LISTING_URI.port) do |http|
    usernames = getuserlist

    usernames.each_with_index do |username,i|
      puts "[#{i} / #{usernames.size}] #{username}"
      downloadRatingDetails(http)
      downloadViewGPG(http)
    end
  end
end

def saveRatings(ratingFileName, identifi, publish)
  begin
    File.open( "#{RATINGDETAILS_DIR}/#{ratingFileName}", "r" ) do |ratingFile|
      ratings = JSON.load( ratingFile )
      
      File.open( "#{VIEWGPG_DIR}/#{ratingFileName}", "r" ) do |userFile|
        ratedUser = JSON.load( userFile )[0]
        return unless ratedUser

        ratedUserName = File.basename(ratingFileName, ".*")

        ratings.each do |rating|
          ratingPacket = Marshal.load(Marshal.dump(IDENTIFI_PACKET))
          ratingPacket[:signedData][:author].push(["account", otcUserID(rating["rater_nick"])])
          ratingPacket[:signedData][:recipient].push(["account", otcUserID(rating["rated_nick"])])
          ratingPacket[:signedData][:rating] = rating["rating"].to_i
          ratingPacket[:signedData][:comment] = rating["notes"]
          ratingPacket[:signedData][:timestamp] = rating["created_at"].to_i
          identifi.savepacketfromdata(ratingPacket.to_json, publish.to_s)
        end

        connections = Marshal.load(Marshal.dump(IDENTIFI_PACKET))
        connections[:signedData][:author].push(["account", otcUserID(ratedUserName)])
        connections[:signedData][:recipient].push(["account", otcUserID(ratedUserName)])
        connections[:signedData][:recipient].push(["nickname", ratedUserName])
        connections[:signedData][:recipient].push(["bitcoin_address", ratedUser["bitcoinaddress"]]) if ratedUser["bitcoinaddress"]
        connections[:signedData][:recipient].push(["gpg_fingerprint", ratedUser["fingerprint"]]) if ratedUser["fingerprint"]
        connections[:signedData][:recipient].push(["gpg_keyid", ratedUser["keyid"]]) if ratedUser["keyid"]
        connections[:signedData][:type] = "connection"
        connections[:signedData][:timestamp] = ratedUser["registered_at"].to_i

        identifi.savepacketfromdata(connections.to_json, publish.to_s)
      end
    end
  rescue Exception => e
    puts "Error saving #{ratingFileName}: #{e.backtrace}"
  end
end

def addToIdentifi(publish=false)
	identifi = IdentifiRPC.new(CONFIG["identifiHost"])

  i = 0
  Dir.foreach(RATINGDETAILS_DIR) do |item|
    next if item == '.' or item == '..'
    saveRatings(item, identifi, publish)
    i += 1
    puts "#{i} #{item}"
  end
end
