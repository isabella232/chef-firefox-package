
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
    attribute(:uri, kind_of: String, default: 'https://download.mozilla.org')
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
      converge_by("installing #{new_resource.version} #{new_resource.language}") do
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
      converge_by("removing #{new_resource.version}") do
        notifying_block do
          remove_package
        end
      end
    end

    def munged_platform
      arch = node['kernel']['machine']
      case new_resource.platform.to_s
      when 'linux'
        (arch == 'x86_64') ? @munged_platform = 'linux64' : @munged_platform = 'linux'
      when 'windows'
        (arch == 'x86_64') ? @munged_platform = 'win64' :  @munged_platform = 'win'
      when 'darwin', /^universal.x86_64-darwin\d{2}$/
        @munged_platform = 'osx'
      else
        @munged_platform = new_resource.platform
      end
    end

    # Explodes tarballs into a path stripping the top level directory from
    # the tarball.
    # @param [String] Full path to tarball to extract.
    # @param [String] Destination path to explode tarball.
    def explode_tarball(filename, dest_path)
      directory dest_path do
        recursive true
      end

      execute 'untar-firefox' do
        command "tar --strip-components=1 -xjf #{filename} -C #{dest_path}"
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

    def file_type(platform)
      if platform.include? 'win'
        '.exe'
      else
        '.tar.bz2'
      end
    end

    def install_package
      require 'uri'

      platform = munged_platform
      download_uri = "#{new_resource.uri}/?product=#{new_resource.version}&os=#{platform}&lang=#{new_resource.language}"
      filename = new_resource.version + file_type(platform)
      cached_file = ::File.join(Chef::Config[:file_cache_path], filename)

      # Splay guard
      unless (::File.exist?(cached_file) && ::File.mtime(cached_file) > Time.now - new_resource.splay && ! ::File.zero?(cached_file))
        remote_file cached_file do
          source URI.encode("#{download_uri}").to_s
          checksum new_resource.checksum unless new_resource.checksum.nil?
          action :create
          notifies :run, 'ruby_block[install-firefox]', :immediately
        end

        # Update file modification time to allow splay checking
        FileUtils.touch cached_file
      end

      # Do the install if we downloaded a new file
      ruby_block 'install-firefox' do
        block do
          if platform.include? 'win'
            windows_installer(cached_file, new_resource.version,
                              new_resource.language, :install)
          else
            package %w{libasound2 libgtk2.0-0 libgtk-3-0 libdbus-glib-1-2 libxt6 libx11-xcb-dev}

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
        action :nothing
      end

    end

    def remove_package
      if munged_platform.include? 'win'
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
