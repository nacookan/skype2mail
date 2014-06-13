#! /usr/bin/ruby
# $ sudo gem install sqlite3-ruby

maindb_original = File.expand_path('~/Library/Application Support/Skype/(Skypeアカウント)/main.db')
maindb = File.expand_path('~/.skype2mail.main.db')
last_filename = File.expand_path('~/.skype2mail.last')
max_days = 10
max_entries = 200

mail_config = {
  :server => 'smtp.example.com',
  :port => 25,
  :from => 'mail@example.com',
  :to => 'your_gmail_account@gmail.com',
}

require 'rubygems'
require 'sqlite3'
require 'net/smtp'
require 'nkf'
require 'fileutils'

include SQLite3

# workdb
FileUtils.copy(maindb_original, maindb)

# load last timestamp
from = 0
if File.exist?(last_filename)
  f = open(last_filename)
  from = f.read.to_i
  f.close
end

# pre query
to = nil
sql = "select timestamp from Messages where ? < timestamp order by timestamp limit 1"
db = Database.new(maindb)
db.execute(sql, from) do |row|
  to_time = Time.at(row[0])
  to = Time.local(to_time.year, to_time.month, to_time.day).to_i + (60 * 60 * 24 * max_days)
end
today = Time.local(Time.now.year, Time.now.month, Time.now.day).to_i
to = today if to == nil || today < to

# main query
sql = <<SQL
  select
    cht.topic,
    con.fullname,
    con.skypename,
    msg.timestamp,
    msg.body_xml
  from
    Messages msg
      inner join Chats cht on msg.chatname = cht.name
      inner join Contacts con on msg.author = con.skypename
  where
        ? < msg.timestamp
    and msg.timestamp < ?
  order by
    msg.timestamp asc
SQL

puts "searching... #{Time.at(from)} - #{Time.at(to)}"
last = from
data = {}
keys = []
db = Database.new(maindb)
db.execute(sql, from, to) do |row|
  chat = "#{row[0]}"
  name = "#{row[1] || row[2]}"
  time = row[3]
  body = "#{row[4]}"
  date = Time.at(time).strftime("%Y-%m-%d")
  keys << date
  data[date] = {} unless data.has_key?(date)
  data[date][chat] = [] unless data[date].has_key?(chat)
  data[date][chat] << [] if data[date][chat].empty? || data[date][chat].last.length == max_entries
  data[date][chat].last << { :name => name, :time => Time.at(time), :body => body }
  last = time
end
db.close

# mail
keys.uniq.sort.each do |date|
  data[date].each do |chat, list|
    list.each_index do |index|
      item = list[index]
      subject = "[skype] #{chat} #{date}" + (2 <= list.length ? " (#{index + 1}/#{list.length})" : "")
      subject_encoded = NKF.nkf('-M -j', subject)
      body =
        "<h1 style=\"margin: 0 0 1em 0; padding: 0.5em; background: #00aff1; color: #ffffff; font-size: 150%;\">" +
        subject +
        "</h1>\r\n"
      item.each do |msg|
        body +=
          "<h2 style=\"margin: 0.5em 0 0.5em 0; font-size: 100%;\">" +
          msg[:time].strftime("%H:%M") + " " +
          msg[:name] + "</h2>\r\n" +
          msg[:body].gsub(/\r\n|\r|\n/, "<br>") +
          "\r\n<hr>\r\n"
      end
      body_encoded = [NKF.nkf('-w8', body)].pack('m')

      mail = <<-MAIL
From: #{mail_config[:from]}
To: #{mail_config[:to]}
Subject: #{subject_encoded}
Date: #{Time::now.strftime("%a, %d %b %Y %X")}
Mime-Version: 1.0
Content-Type: text/html; charaset=utf-8
Content-Transfer-Encoding: base64

#{body_encoded}
      MAIL

      puts "sending... #{subject} : #{item.count} entries."
      Net::SMTP.start(mail_config[:server], mail_config[:port]) do |smtp|
        smtp.send_mail mail, mail_config[:from], mail_config[:to]
      end
      sleep 1
    end
  end
end

# save last timestamp
f = File.open(last_filename, 'w')
f.puts last
f.close
