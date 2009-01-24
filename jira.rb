#!/usr/bin/env ruby
# ypetya@gmail.com
#
# == Installation ==
#
# To get this working, first install a few gems:
#
#     $ gem install soap4r
#
# Now, jira4r, which has to be pulled down from subversion:
#
#     $ svn co http://svn.rubyhaus.org/jira4r/trunk jira4r
#     $ cd jira4r
#     $ gem build jira4r.gemspec
#     $ gem install jira4r-*.gem
#
# example:
# http://svn.atlassian.com/fisheye/browse/public/contrib/jira/rt3-exporter/trunk/util/notifyImportedUsers.rb?r=26539
#
# == Config ==
#
# Config file contains my jira_user and jira_password in form of:
# @@settings => { :jira=>['user','password'],
#   :jira_service =>{ :jira=>'url', :filer=>'filter_id_from_jira'
# }
# filter_id: if you create a filter in Jira, you can find this id in the url
load '/etc/my_ruby_scripts/settings.rb'
#
# and the show must go on...
#
require 'jira4r/jira_tool'
# jira server & own filter settings
@@service = @@settings[:jira_service]

# task counter
@@counter = 0

# {{{ jira and user parameters
@@jira = @@service[:jira]
@@filter = @@service[:filter]
@@user = @@settings[:jira].first
@@pwd = @@settings[:jira].last
# }}}

# {{{ default settings display=short
@@find = nil
@@key = nil
@@display = 'short'
@@total = 'false'
@@description = 'false'
@@reporter = 'false'
# }}}

# {{{ ARGV parser and minimal help
begin
  ARGV.each do |arg|
    a = arg.split '='
    throw 'err' unless a.size==2
    eval "@@#{a.first}='#{a.last}'"
  end if ARGV.size > 0
  if @@display == 'full'
    @@reporter,@@description,@@total = * %w{true true true}
  end
rescue
  puts <<-EOT
Usage: 
Optional parameter arguments format: param=value"

Call jira.rb with 

 * jira=jira_url 
    override default jira url
 * filter=filter_number 
    override/set jira filter id
 * user=user_name 
    override default jira user name
 * pwd=jira_pwd 
    override default jira password
 * display=short|detail 
    display short makes issue number, summary list.(default setting)
    display full prints out all information
 * total=true|false 
    display found issues count
 * description=true|false 
    display description
 * reporter=true|false 
    display reporter
 * key=issue_key 
    key searches for jira issue find is a regex key
 * find=search_regex
    find searches for jira issue find is a regex in summary or description or reporter
EOT
  exit
end
# }}}

# {{{ logger
@@log = Logger.new(STDOUT)
@@log.level = Logger::ERROR
# }}}

def match find,key,issue
  return true unless find or key
  return true if find and (issue.summary + issue.reporter + issue.key) =~ /#{find}/i
  return true if key and (issue.key =~ /#{key}/i)
  false
end

def list find=nil,key=nil
  @counter = 0
  #main listing
  jira = Jira4R::JiraTool.new(2, @@jira)
  jira.logger= @@log
  jira.login @@user,@@pwd
  jira.getIssuesFromFilter(@@filter).each do |issue|
    next if not match find,key,issue
    @@counter += 1
    puts "#{issue.key} : #{issue.summary}"
    puts "Reporter : #{issue.reporter}" if @@reporter == 'true'
    if @@description == 'true'
      puts '-' * 20
      puts "DESCRIPTION:\r\n#{issue.description}" 
      puts '.'
    end
    #puts issue.inspect
  end

  # total count
  puts "Total: #{@@counter} tasks found." if @@total=='true'
end

list @@find,@@key
