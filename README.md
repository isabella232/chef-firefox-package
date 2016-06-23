# firefox_package

[![Build Status](https://travis-ci.org/rapid7-cookbooks/firefox_package.svg)](https://travis-ci.org/rapid7-cookbooks/firefox_package)
[![Cookbook Version](https://img.shields.io/cookbook/v/firefox_package.svg)](https://supermarket.chef.io/cookbooks/firefox_package)
[![License](https://img.shields.io/badge/license-Apache_2-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)


This cookbook provides the ```firefox_package``` provider which can be used
to install any version of firefox, including named versions such as 'latest-esr'
for multiple platforms.

## Supported Platforms

- Linux
- Windows

## Attributes

<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>['firefox_package']['firefox'][_version_][_language_]</tt></td>
    <td>String</td>
    <td>Linux Only: Path to Firefox installation, where version is the requested version and language is the requested language. This is primarly used for uninstall purposes.</td>
    <td><tt>"/opt/firefox/#{version}_en-US"</tt></td>
  </tr>
</table>

## Resources

### firefox_package

Install the latest version of Firefox via the Mozilla Firefox download API:
* https://download-installer.cdn.mozilla.net/pub/firefox/releases/latest/README.txt

```ruby
firefox_package 'firefox-latest'
```

Configure a 24 hour splay to reduce egress HTTPS requests to Mozilla servers.
```ruby
firefox_package 'firefox-esr-latest' do
  splay 84600
end
```

* `version`   - Version of Firefox to install. Named versions, such as `firefox-latest`, `firefox-esr-latest`, `firefox-38.0`  are all valid. *(name_attribute)*
* `checksum`  - SHA256 Checksum of the file. Not required.
* `uri`       - HTTPS uri to obtain the installer/archive. Defaults to: `https://download.mozilla.org`
* `language`  - Language desired. Defaults to: `en-US`
* `platform`  - Platform you wish to download and install. Defaults to the OS from which Chef is running.
* `path`      - Path to install Firefox. Linux Only, Defaults to: ```/opt/firefox/#{version}_#{language}```
* `splay`     - Time in minutes to wait before next contact to Mozilla servers. Not required, defaults to 0 (zero) seconds.
* `link`      - Create the specfied symlink (Linux Only). This can be an array to create multiple symlinks to the same instance, or a string for a single symlink.


## License and Authors

Author:: Rapid7, LLC (<ryan_hass@rapid7.com>)
