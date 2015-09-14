#!/usr/bin/env ruby
#encoding=UTF-8
require 'net/http'
require 'cgi'
require 'json'
require 'time'
require 'yaml'
require 'nokogiri'
require 'fileutils'
class UnionRemove
        attr_reader :requests,:records
        @@home=File.join Dir.home,".tieba","union_remove"
        @@requests_file=File.join @@home,"requests.yaml"
        @@records_file=File.join @@home,"records.yaml"
        def initialize config={}
                FileUtils.mkpath @@home unless Dir.exists? @@home
                @members=config[:members]
                @least=config[:least]
                @new_records=[]
                @logger=Logger.new File.join(Dir.home,".tieba","cookies",config[:username]+".cookies")
                @requests=File.exists?(@@requests_file) ? YAML.load_file(@@requests_file) : []
                @records=File.exists?(@@records_file) ? YAML.load_file(@@records_file) : []

                res1=@logger.webget "/i/atme"
                /(\/i\/sys\/.*)$/===res1.header["location"]
                res2=@logger.webget $1
                /\/i\/(\d*)\?fr=home/===res2.header["location"]
                res=@logger.webget "/i/#{$1}/atme"
                doc=Nokogiri::HTML.parse res.body
                @requests |= doc.xpath("//li[@class='feed_item clearfix feed_atme j_feed_atme']").map{|d|
                        /^(.+?)：$/===d.at(".//div[@class='atme_text clearfix j_atme']/div[@class='atme_user']").text
                        user=$1
                        text=d.at(".//div[@class='atme_text clearfix j_atme']/div[@class='atme_content']").text
                        title=d.at(".//a[@class='itb_thread']").text
                        /^\/p\/(\d*)$/===d.at(".//a[@class='itb_thread']")["href"]
                        kz=$1
                        time=DateTime.strptime d.at("//div[@class='feed_time']").text,"%m-%d %H:%M"
                        {
                                :user=>user,
                                :type=>$1.intern,
                                :kz=>kz,
                                :title=>title,
                        } if @members.include? user and /(delete|cancel)/===text
                }.select{|x| x!=nil}
                @requests.sort_by{|r| r[:type]==:delete ? 0 : 1}.each{|req|
                        if t=@records.detect{|r| r[:kz]==req[:kz]}
                                next if t[req[:type]].include? req[:user]
                                if req[:type]==:delete
                                        t[:count]+=1
                                elsif req[:type]==:cancel
                                        t[:count]-=1
                                end
                                t[req[:type]].push(req[:user])
                        elsif req[:type]==:delete
                                @records.push   :kz=>req[:kz],
                                                :title=>req[:title],
                                                :count=>1,
                                                :delete=>[req[:user]],
                                                :cancel=>[],
                                                :done=>false
                        end
                }
        end
        def check kz
                @records.detect{|t| t[:kz]==kz and not t[:done]  and t[:count]>=@least}
        end
        def mark kz
                t=@records.detect{|r| r[:kz]==kz and not r[:done]}
                t[:done]=true if t
        end
        def [] kz
                @records.detect{|r| r[:kz]==kz}
        end
        def save
                File.write @@requests_file,@requests.to_yaml
                File.write @@records_file,@records.to_yaml
        end
end
