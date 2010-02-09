#!/usr/bin/env ruby
# :title:JiraConsole
#
# == Installation
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
# == Config
#
# Config file contains my jira_user and jira_password in form of:
#
#   @@settings => { :jira=>['user','password'],
#     :jira_service =>{ :jira=>'url', :filer=>'filter_id_from_jira'
#   }
#
# filter_id: if you create a filter in Jira, you can find this id in the url
load '/etc/my_ruby_scripts/settings.rb'

require 'jira4r/jira_tool'
require 'yaml'

# This class can store different intervals for one issue 
class TaskStopper

  attr_accessor :task, :time_intervals, :current_start

  def initialize key
    @task = key
    @time_intervals = []
    @current_start = nil
  end

  def start
    return false if on? 
    @current_start = Time.now
  end

  def stop
    return false unless on? 
    @time_intervals << (Time.now - @current_start)
    @current_start = nil
  end

  def total_minutes
    sum = 0
    @time_intervals.each{|i| sum += i }
    return sum / 60
  end

  def on?
    @current_start ? true : false
  end

  def display
    "#{@key} : Timer is #{ on? ? 'ON' : 'OFF'} measured #{total_minutes} total minutes."
  end
end

class JiraConsole
  attr_accessor :errors, :stoppers

  # {{{ HELP message
  HELP = <<-EOT
  Usage: 

  Optional parameter arguments format: param=value

  Call jira.rb <command> <arguments>


  COMMANDS: (optional)

   * list
       display jira issues (default command) 
   * comment
       post new comment on task
   * log
       posts worklog
   * help
       displays this help message
   * open
       opens jira task in browser
   
   Timer commands

   * start
       starts a timer for an issue
   * stop 
       stops all timers
   * push 
       push timers logged times to jira
   * clear
       clear a timer data

  ARGUMENTS:

  if you left one of the required arguments, 
  jira-console tries to start your default editor ENV["EDITOR"] or vim.

  arguments for command 'comment'

   * key=issue_key
   * message=<string message>
   
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
   * display=short|comments|full|worklogs 
      - display short makes issue number, summary list.(default setting)
      - display short with comments
      - display full prints out all information
      - display worklogs prints out short format with worklog ingormation
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

  arguments for command 'start'
    * key=issue_key

  arguments for command 'open'
    * key=issue_key

EOT
  # }}}
  COMMANDS = [:log,:list,:help,:comment,:fixlog,:start,:stop,:push,:clear,:open]

  CONFIG_FILE = File.join(File.expand_path('~'), 'jira.yml')

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

  # {{{ jira and user parameters

  def load_stoppers
    if File.exists?(CONFIG_FILE)
      @stoppers = YAML::load_file(CONFIG_FILE)
    else
      @stoppers = []
    end

    sum = 0
    on = []
    @stoppers.each do |stopper|
      on << stopper.task if stopper.on?
    end

    if @stoppers.length > 0
      puts "There are #{@stoppers.length} stoppers."
      
      puts( "Active stoppers:( #{on.length} : #{on.join(', ')} ).")  if on.length > 0
    else
      puts "No stoppers."
    end
  end

  def load_parameters
    return false unless (@service.keys & [:jira,:filter]).size == 2
    @jira = @service[:jira]
    @filter = @service[:filter]
    @user = @settings[:jira].first
    @pwd = @settings[:jira].last
   
    load_stoppers

    true
  rescue
    false
  end

  def save_stoppers
    File.open(CONFIG_FILE,'w') do |f|
      f.puts @stoppers.to_yaml
    end
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

# {{{ command execution
  
  def success?
    errors.empty?
  end

  def my_method_caller method, *args
    (args.empty? ? send(method) : send(method,*args))
  end

  def call_with_err method,*args
    return unless success?
    @errors << method unless my_method_caller method,*args
  end

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
# }}}

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

  # {{{ command helpers

  def check_required param
    a=instance_eval("defined?(@#{param})")
    return if a and not a.empty?
    filename = "#{param}.jira.tmp"
    system("echo \"\# please enter missing parameter or parameters in standard YAML format\n#{param}:\n\" > #{filename}")
    cmd = "#{ENV['EDITOR'] || 'vim'} #{filename}"
    
    system("#{cmd}")
    hash = YAML.load_file(filename)
   
    throw 'not valid yaml format! try: "param: value"' unless defined?(hash.keys)

    hash.keys.each do |k|
      eval("@#{k}='#{hash[k]}'")
      puts "#{k} parameter loaded"
    end
    system("rm #{filename}")
  end

  def match find,key,issue
    return true unless find or key
    return true if find and (issue.summary + issue.reporter + issue.key) =~ /#{find}/i
    return true if key and (issue.key =~ /#{key}/i)
    false
  end

  def get_comments issue
    @jira4r.getComments( issue.key ).each do |comment|
      puts "-> #{comment.author} commented at #{comment.updated.strftime("%Y. %b %e., %H:%M")}:"
      puts comment.body
    end
  end

  def get_worklogs issue
    @jira4r.getWorklogs( issue.key ).each do |worklog|
      puts "#{worklog.author}(#{worklog.timeSpent}) : #{worklog.comment}"
    end
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
# }}}

# {{{ commands

  def start
    sel = @stoppers.select{|s| s.task == @key}
    if sel.empty?
      sel = [ TaskStopper.new(@key) ]
      @stoppers << sel.first
    end
    sel.first.start

    save_stoppers

    puts "Timer started for #{@key}"
    true
  rescue
    false
  end

  def stop
    @stoppers.each{|s| s.stop}

    save_stoppers

    puts "All timer stopped."
    true
  rescue
    false
  end

  def clear
    @stoppers = []

    save_stoppers

    puts "All timer cleared."
    true
  rescue
    false
  end

  def push
    stop
    
    @stoppers.each do |stopper|
      @key = stopper.task
      @time = "#{stopper.total_minutes.to_i}m"
      @message = ''
      unless log
        puts "can not log for #{@key} : #{@time} "
      end
    end

    puts "All timers pushed."

    clear
    true
  rescue
    false
  end
  
  # This command will print out the informations from jira
  def list
    @counter = 0
    #main listing
    @jira4r.getIssuesFromFilter(@filter).each do |issue|
      next if not match @find,@key,issue
      @counter += 1
      puts "#{issue.key} : #{issue.summary}"
      puts "Reporter : #{issue.reporter}" if @reporter == 'true'
      puts "DESCRIPTION:\r\n#{issue.description}" if @description == 'true'
      get_comments(issue) if %w{full comments}.include? @display
      get_worklogs(issue) if %w{full worklogs}.include? @display
      puts '.' if @description == 'true'
    end

    # total count
    puts "Total: #{@counter} tasks found." if @total=='true'
    true
  rescue
    false
  end

  # This command helps to create new worklogs
  def log
    %w{key message time}.each{|p| check_required(p) }
    wl = Jira4R::V2::RemoteWorklog.new
    wl.comment = @message
    wl.startDate = Time.now
    wl.timeSpent = @time
    @jira4r.addWorklogAndAutoAdjustRemainingEstimate(@key.upcase, wl)

    puts "#{@key.upcase} - '#{@message}' : #{@time} logged"
    true
  rescue
    false
  end

  # This command helps creating comments on issue
  def comment
    %w{key message}.each{|p| check_required p }
    c= Jira4R::V2::RemoteComment.new
    c.body= @message
    @jira4r.addComment(@key.upcase,c)
    puts " #{@key.upcase} - #{@message}"
    puts "Comment added"
    true
  rescue
    false
  end

  def open
    check_required 'key'
    system( 'xdg-open', "#{@service[:jira]}/browse/#{@key.upcase}")
    true
  rescue
    false
  end

  # This command helps you to create avarage worklog time for a day
  def fixlog
    %w{date total_hours keys}.each{|p| check_required p}
    throw 'not implemented yet!'
    @keys.spit(',').each do |key|
      @jira4r.getWorklogs( key ).each do |worklog|
        if worklog.author == @user
          puts worklog.inspect
          puts "#{worklog.author}(#{worklog.timeSpent}) : #{worklog.comment}"
        end
      end
    end
  end
  # }}}
  

end

j = JiraConsole.new(@@settings,ARGV)
j.run!
