# Ensure we have an up to date repo cache.
include_recipe 'apt' if platform_family?('debian')

{
  'firefox-esr-latest' => [ '/usr/bin/firefox-esr-latest' ],
  'firefox-latest' => [ '/usr/bin/firefox-latest' ],
  '37.0' => [ '/usr/bin/firefox-37.0' ]
}.map do |version, linkto|
  firefox_package version do
    link linkto
  end
end

# Copy an old version into a new version named directory to test
# upgrading without having to worry about the paths.
# There has to be a better way to copy directories... but it is not obvious.
unless platform?('windows')
  execute "copy-version" do
    command 'cp -a /opt/firefox/37.0_en-US /opt/firefox/38.0_en-US'
  end

  firefox_package '38.0' do
    action :upgrade
  end
end

include_recipe 'firefox_package_test::default_controls'

