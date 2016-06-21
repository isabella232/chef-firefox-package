
# Cookbook Name:: firefox_package
# Recipe:: default
#
# Copyright (C) 2014 Rapid7, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'poise'
require 'chef/resource'
require 'chef/provider'

module FirefoxPackage
  class Resource < Chef::Resource
    include Poise
    include Chef::DSL::PlatformIntrospection
    provides(:firefox_package)
    actions(:install, :upgrade, :remove)

    attribute(:version, kind_of: String, name_attribute: true)
    attribute(:checksum, kind_of: String)
    attribute(:uri, kind_of: String, default: 'https://download-installer.cdn.mozilla.net/pub/firefox/releases')
    attribute(:language, kind_of: String, default: 'en-US')
    attribute(:platform, kind_of: String, default: lazy { node['os'] })
    attribute(:path, kind_of: String,
              default: lazy { platform_family?('windows') ? "C:\\Program Files (x86)\\Mozilla Firefox\\#{version}_#{language}" : "/opt/firefox/#{version}_#{language}" })
    attribute(:splay, kind_of: Integer, default: 0)
    attribute(:link, kind_of: [String, Array, NilClass])
    attribute(:windows_ini_source, kind_of: String, default: 'windows_ini_source')
    attribute(:windows_ini_content, kind_of: String, default: lazy { { :install_path => self.path } })
    attribute(:windows_ini_cookbook, kind_of: String, default: 'firefox_package')
  end

  class Provider < Chef::Provider
    include Poise
    include Chef::DSL::PlatformIntrospection
    provides(:firefox_package)

    def action_install
      converge_by("installing Firefox #{new_resource.version} #{new_resource.language}") do
        notifying_block do
           install_package
        end
      end
    end

    def action_upgrade
      converge_by("upgrading Firefox to version #{new_resource.version}") do
        notifying_block do
          install_package
        end
      end
    end

    def action_remove
      converge_by("removing Firefox #{new_resource.version}") do
        notifying_block do
          remove_package
        end
      end
    end

    def munged_platform
      case new_resource.platform.to_s
      when 'x86_64-linux', 'linux'
        if esr?(new_resource.version) or latest?(new_resource.version)
          @munged_platform = 'linux64'
        else
          @munged_platform = 'linux-x86_64'
        end
      when 'i386-mingw32', 'windows'
        @munged_platform = 'win32'
      when 'darwin', /^universal.x86_64-darwin\d{2}$/
        @munged_platform = 'mac'
      else
        @munged_platform = new_resource.platform
      end
    end

    # Explodes tarballs into a path stripping the top level directory from
    # the tarball. This has a not_if guard which prevents exploding when a
    # pre-existing version is on disk and is the same or newer.
    # @param [String] Full path to tarball to extract.
    # @param [String] Destination path to explode tarball.
    def explode_tarball(filename, dest_path)
      directory dest_path do
        recursive true
      end

      execute 'untar-firefox' do
        command "tar --strip-components=1 -xjf #{filename} -C #{dest_path}"
        not_if {
          installed_version(
            ::File.join(dest_path, 'firefox')
          ) >= parse_version(filename)
        }
      end
    end

    # Obtain version string from an installed version.
    # @param [String] Path the Firefox executable.
    # @return [Gem::Version] Returns the installed version, or 0.0 if not
    # installed in the specified path.
    def installed_version(path)
      if ::File.executable?(path)
        require 'mixlib/shellout'

        cmd = Mixlib::ShellOut.new(path, '--version')
        cmd.run_command

        version = parse_version(cmd.stdout)
      else
        version =  parse_version('0.0')
      end

      version
    end

    # Parse the version number from a given string.
    # @param [String] String containing a Firefox version.
    # @return [Gem::Version] Returns a Versonomy::Value object which
    # can be used for comparing versions like 38.0 and 38.0.0.
    def parse_version(str)
      version_string = /.\d\.\d.\d|\d+.\d/.match(str).to_s
      Gem::Version.new(version_string)
    end

    # Appends ESR to the version string when an ESR version is installed.
    # This is done so the value can be matched against the Windows registry
    # key value to make the installation idempotent.
    # @param [String] Version value as a string.
    # @return [String] When version is an ESR, the value is returned with the
    # string EST appended.
    def windows_long_version(version)
      if version.nil?
        version = parse_version(filename)
        long_version = version.to_s
        if esr?(filename)
          long_version = "#{parse_version(filename)} ESR"
        end
      else
        long_version = version
      end
    end

    # Determines if the version is a latest version.
    # @param [String]
    # @return [Boolean]
    def latest?(filename)
      if filename =~ /latest/
        true
      else
        false
      end
    end

    # Determines if the version is an ESR version.
    # @param [String]
    # @return [Boolean]
    def esr?(filename)
      if filename =~ /esr/
        true
      else
        false
      end
    end

    def windows_installer(filename, version, lang, req_action)
      rendered_ini = "#{Chef::Config[:file_cache_path]}\\firefox-#{version}.ini"

      template rendered_ini do
        source new_resource.windows_ini_source
        variables new_resource.windows_ini_content
        cookbook new_resource.windows_ini_cookbook
      end

      windows_package "Mozilla Firefox #{windows_long_version(version)} (x86 #{lang})" do
        source filename
        installer_type :custom
        options "/S /INI=#{rendered_ini}"
        action req_action
      end
    end

    def requested_version_filename(download_uri)
      unless platform_family?('windows')
        include_recipe 'build-essential::default'
      end

      chef_gem 'oga' do
        compile_time true
      end

      require 'net/http'
      require 'oga'
      require 'digest/sha1'

      uri = URI.parse(download_uri)
      # Mozilla uses an object store which seems to expect trailing slashes
      # to requrest a file index.
      uri.path = "#{uri.path}/" unless uri.path.end_with?('/')
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.port == 443
        http.use_ssl = true
        http.ssl_version = :TLSv1
        http.ca_file = Chef::Config[:ssl_ca_file] if Chef::Config[:ssl_ca_file]
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      cached_filename = ::File.join(Chef::Config[:file_cache_path], ::Digest::SHA1.hexdigest(download_uri))

      if ::File.exist?(cached_filename) && ::File.mtime(cached_filename) > Time.now - new_resource.splay && ! ::File.zero?(cached_filename)
        ::File.read(cached_filename)
      else
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        raise response.error! if response.code.to_i >= 400
        doc = Oga.parse_html(response.body)
        remote_filename = doc.xpath('//tr/td/descendant::*/text()').to_a.delete_if { |element|
          element.text.match('Stub') || element.text.match('\.\.')
        }.last.text

        if doc.nil? || remote_filename.empty?
          raise StandardError, "The server #{uri.host} responded from #{uri.path} with an unexpected document:\n #{response.body}"
        else
          converge_by("Updating Firefox filename cache: #{cached_filename} with content: #{remote_filename}") do
            file cached_filename do
              content remote_filename
            end
          end
        end
        remote_filename
      end
    end

    def install_package
      require 'uri'

      platform = munged_platform
      # If the version contains ESR or latest, handle it accordingly
      if esr?(new_resource.version) or latest?(new_resource.version)
        download_uri = "https://download.mozilla.org/?product=#{new_resource.version}&os=#{platform}&lang=#{new_resource.language}"
        filename = new_resource.version
      else
        download_uri = "#{new_resource.uri}/#{new_resource.version}/#{platform}/#{new_resource.language}/"
        filename = requested_version_filename(download_uri)
        download_uri = download_uri + filename
      end
      cached_file = ::File.join(Chef::Config[:file_cache_path], filename)

      remote_file cached_file do
        source URI.encode("#{download_uri}").to_s
        checksum new_resource.checksum unless new_resource.checksum.nil?
        action :create
      end

      if platform == 'win32'
        windows_installer(cached_file, new_resource.version,
                          new_resource.language, :install)
      else
        package %w{libasound2 libgtk2.0-0 libdbus-glib-1-2 libxt6}

        explode_tarball(cached_file, new_resource.path)
        node.set['firefox_package']['firefox']["#{new_resource.version}"]["#{new_resource.language}"] = new_resource.path.to_s
        unless new_resource.link.nil?
          if new_resource.link.is_a?(Array)
            new_resource.link.each do |i|
              link i do
                to ::File.join(new_resource.path, 'firefox').to_s
              end
            end
          else
            link new_resource.link do
              to ::File.join(new_resource.path, 'firefox').to_s
            end
          end
        end
      end
    end

    def remove_package
      if munged_platform == 'win32'
        windows_installer(nil, new_resource.version,
                          new_resource.language, :remove)
      else
        directory node['firefox_package']['firefox']["#{new_resource.version}"]["#{new_resource.language}"] do
          recursive true
          action :delete
        end
      end
    end
  end
end
