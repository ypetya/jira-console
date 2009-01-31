#!/usr/bin/ruby

# configuration file /etc/subversion/svn-worklog.conf:
# 
# $username = "issues"
# $password = "secret"


require 'rubygems'
require 'jira4r/jira_tool'
load '/etc/subversion/svn-worklog.conf'

class Worklog
  
  attr_accessor :issue, :time, :comment

  def initialize(issue, time, comment="")
    @issue = issue
    @time = time
    @comment = comment
  end

  def post(jira)
    begin
      remoteWorklog = Jira4R::V2::RemoteWorklog.new
      remoteWorklog.comment = @comment + "\ncreated from svn"
      remoteWorklog.startDate = Time.now
      remoteWorklog.timeSpent = @time 
      jira.addWorklogAndAutoAdjustRemainingEstimate(@issue, remoteWorklog)
    rescue SOAP::Error => error
      STDERR.puts("Error: " + error)
    end
  end

  def to_s
    "[#{@issue}] #{@time} (#{@comment})"
  end
end

if $*.size != 2
then
  STDERR.puts("usage: #{$0} repos revision")
  exit 1
end
repos = $*[0]
revision = $*[1]

author = `svnlook -r "#{revision}" author "#{repos}"`.strip
log = `svnlook -r "#{revision}" log "#{repos}"`.strip

issue = nil
comment = ""
worklogs = {}

log.each do |line|
  line.strip!
  if line =~ /^\[([A-Z]+-[0-9]+)\]/
  then
    issue = $1
    comment = ""
  end
  time = $1 if line =~ /\(((\d+[wdhm])+)\)$/
  comment += line + "\n"
  worklogs[issue] = Worklog.new(issue,time,comment.chomp) if issue and time
end

if worklogs.size > 0
then
  logger = Logger.new(STDERR)
  logger.sev_threshold = Logger::WARN
  jira = Jira4R::JiraTool.new(2, "https://secure.reucon.net/issues")
  jira.logger = logger
  jira.driver.options["protocol.http.ssl_config.verify_mode"] = nil
  jira.enhanced = true
  jira.login($username + ":" + author, $password)

  worklogs.each_value do |w| w.post(jira) end
end

