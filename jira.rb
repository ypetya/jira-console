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

class JiraConsole
  attr_accessor :errors

  # {{{ HELP message
  HELP = <<-EOT
  Usage: 

  Optional parameter arguments format: param=value"

  Call jira.rb <command> <arguments>


  COMMANDS: (optional)

   * list
      display jira issues (default command) 
   * log
      posts worklog to jira
   * help
      displays this help message


  ARGUMENTS:
   
  aguments for command 'log'
  
   * key=issue_key
   * time=<jira time format>
   * message=<string message>

  optional arguments for command 'list'

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
  # }}}
  COMMANDS = [:log,:list,:help]

  def initialize settings,args
    @errors = []
    @command = []
    # jira server & own filter settings
    @settings = settings
    @service = settings[:jira_service]
    # task counter
    @counter = 0

    call_with_err :load_parameters
    call_with_err :parse,*args
    log_errors
  end

  def my_method_caller method, *args
    (args.empty? ? send(method) : send(method,*args))
  end

  def call_with_err method,*args
    return unless success?
    @errors << method unless my_method_caller method,*args
  end

  def success?
    errors.empty?
  end

  # {{{ jira and user parameters
  def load_parameters
    return false unless (@service.keys & [:jira,:filter]).size == 2
    @jira = @service[:jira]
    @filter = @service[:filter]
    @user = @settings[:jira].first
    @pwd = @settings[:jira].last
  end
  # }}}

  # {{{ default settings display=short
  def load_defaults!
    @key,@time,@message=nil,nil,nil
    @find = nil
    @key = nil
    @display = 'short'
    @total = 'false'
    @description = 'false'
    @reporter = 'false'
  end
  # }}}

  def valid_command?
    return false if @command.empty?
    COMMANDS.include? @command.first
  end

  def run!
    return unless success?
    call_with_err :init_jira
    call_with_err @command.first
    log_errors
  end

  def log_errors
    puts "Errors: #{@errors.join(',')}." unless success?
  end

  # {{{ ARGV parser and minimal help
  def parse *args
    load_defaults!
    args.each_with_index do |arg,index|
      #puts arg.inspect
      a = arg.split '='
      if index==0 and a.size != 2
        @command << a.first.downcase.to_sym
        @errors << :command unless valid_command?
        throw 'err' unless success?
        next
      end
      throw 'err' unless a.size==2
      if a.first == 'message'
        eval "@#{a.first}='#{arg[8..1008]}'"
      else
        eval "@#{a.first}='#{a.last}'"
      end
    end 
    if @display == 'full'
      @reporter,@description,@total = * %w{true true true}
    end
    @command << :list if @command.empty?
    true
  rescue
    false
  end
  # }}}

  # {{{ logger
  def create_logger
    @log = Logger.new(STDOUT)
    @log.level = Logger::ERROR
  end
  # }}}

  def match find,key,issue
    return true unless find or key
    return true if find and (issue.summary + issue.reporter + issue.key) =~ /#{find}/i
    return true if key and (issue.key =~ /#{key}/i)
    false
  end

  def init_jira
    create_logger
    @jira4r = Jira4R::JiraTool.new(2, @jira)
    @jira4r.logger= @log
    @jira4r.login @user,@pwd
    true
  rescue
    false
  end

  def help
    puts HELP
    true
  end

  def list
    @counter = 0
    #main listing
    @jira4r.getIssuesFromFilter(@filter).each do |issue|
      next if not match @find,@key,issue
      @counter += 1
      puts "#{issue.key} : #{issue.summary}"
      puts "Reporter : #{issue.reporter}" if @reporter == 'true'
      if @description == 'true'
        puts '-' * 20
        puts "DESCRIPTION:\r\n#{issue.description}" 
        puts '.'
      end
      #puts issue.inspect
    end

    # total count
    puts "Total: #{@counter} tasks found." if @total=='true'
    true
  rescue
    false
  end

  def log

    wl = Jira4R::V2::RemoteWorklog.new
    wl.comment = @message + "\ncreated from jira-console"
    wl.startDate = Time.now
    wl.timeSpent = @time
    @jira4r.addWorklogAndAutoAdjustRemainingEstimate(@key, wl)

    puts "#{@key} - '#{@message}' : #{@time} logged"
    true
  rescue
    false
  end
end

j = JiraConsole.new(@@settings,ARGV)
j.run!
