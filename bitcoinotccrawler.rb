require 'rubygems'
require 'nokogiri'
require 'net/http'
require 'json'
require './identifirpc.rb'

USER_LIST_FILE = "bitcoin-otc-data/bitcoin-otc-wot.html"
RATINGDETAILS_DIR = "bitcoin-otc-data/ratingdetails"
VIEWGPG_DIR = "bitcoin-otc-data/viewgpg"
LISTING_URI = URI("http://bitcoin-otc.com/viewratings.php")
IDENTIFI_HOST = 'http://identifirpc:FLg69hEBwf778rC4dSLEzdMtoyt41Ea8akffmGKHPLuf@127.0.0.1:8332'

def ratingsJsonUrl(nickname)
  "http://bitcoin-otc.com/viewratingdetail.php?nick=#{nickname}&sign=ANY&type=RECV&outformat=json"
end

def userJsonUrl(nickname)
  "http://bitcoin-otc.com/viewgpg.php?nick=#{nickname}&outformat=json"
end

def userID(nickname)
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

def saveRatings(ratingFileName, identifi)
    File.open( "#{RATINGDETAILS_DIR}/#{ratingFileName}", "r" ) do |ratingFile|
      ratings = JSON.load( ratingFile )
      
      File.open( "#{VIEWGPG_DIR}/#{ratingFileName}", "r" ) do |userFile|
        user = JSON.load( userFile )[0]
        
        ratings.each do |rating|
          identifi.savepacket("account", userID(rating["rater_nick"].to_s), "account", userID(rating["rated_nick"].to_s), rating["notes"].to_s, rating["rating"].to_s)
        end

        return unless user

        userName = File.basename( ratingFileName, ".*" )
        identifi.saveconnection("url", "bitcoin-otc.com", "account", userID(userName), "bitcoinaddress", user["bitcoinaddress"].to_s) if user["bitcoinaddress"]
        identifi.saveconnection("url", "bitcoin-otc.com", "account", userID(userName), "gpg_fingerprint", user["fingerprint"].to_s) if user["fingerprint"]
        identifi.saveconnection("url", "bitcoin-otc.com", "account", userID(userName), "nickname", userName)
      end
    end
end

def addToIdentifi
	identifi = IdentifiRPC.new(IDENTIFI_HOST)

  i = 0
  Dir.foreach(RATINGDETAILS_DIR) do |item|
    next if item == '.' or item == '..'
    saveRatings(item, identifi)
    i += 1
    puts "#{i} #{item}"
  end
end