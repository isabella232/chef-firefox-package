control_group 'Firefox Installation' do
  if ['debian', 'ubuntu'].include?(os[:family])
    control 'latest-esr' do
      subject(:latest_esr) { command('/opt/firefox/firefox-esr-latest_en-US/firefox --version') }
      it 'is installed and symlinked' do
        expect(file('/usr/bin/firefox-esr-latest')).to be_symlink
        expect(file('/usr/bin/firefox-esr-latest')).to be_linked_to('/opt/firefox/firefox-esr-latest_en-US/firefox')
        expect(file('/opt/firefox/firefox-esr-latest_en-US/firefox')).to be_executable
        expect(latest_esr.exit_status).to eq(0)
      end
    end

    control 'latest' do
      subject(:latest) { command('/opt/firefox/firefox-latest_en-US/firefox --version') }

      it 'is installed and symlinked' do
        expect(file('/usr/bin/firefox-latest')).to be_symlink
        expect(file('/usr/bin/firefox-latest')).to be_linked_to('/opt/firefox/firefox-latest_en-US/firefox')
        expect(file('/opt/firefox/firefox-latest_en-US/firefox')).to be_executable
      end

      it 'is functional when invoked' do
        expect(latest.exit_status).to eq(0)
      end
    end

    control '37.0' do
      subject(:specified_version) { command('/opt/firefox/firefox-37.0_en-US/firefox --version') }

      it 'is installed and symlinked' do
        expect(file('/usr/bin/firefox-37.0')).to be_symlink
        expect(file('/usr/bin/firefox-37.0')).to be_linked_to('/opt/firefox/firefox-37.0_en-US/firefox')
        expect(file('/opt/firefox/firefox-37.0_en-US/firefox')).to be_executable
      end

      it 'is functional when invoked' do
        expect(specified_version.exit_status).to eq(0)
      end

      it 'is the correct version of Firefox'do
        expect(specified_version.stdout).to match(/Mozilla Firefox 37.0/)
      end
    end

    control 'Upgrade 37.0 to 38.0' do
      subject(:upgraded_version) { command('/opt/firefox/firefox-38.0_en-US/firefox --version') }

      it 'is functional when invoked after upgrade' do
        expect(upgraded_version.exit_status).to eq(0)
      end

      it 'is succsessful' do
        expect(upgraded_version.stdout).to match(/Mozilla Firefox 38.0/)
      end
    end
  elsif os[:family] == 'windows'
    control 'latest-esr' do
      let(:bin_path) { 'C:\Program Files (x86)\Mozilla Firefox\latest-esr_en-US\firefox.exe' }
      subject(:latest_esr) { command( "\"#{bin_path}\" --version") }

      it 'is installed' do
        expect(file(bin_path)).to be_file
      end
    end

    control 'latest' do
      let(:bin_path) {'C:\Program Files (x86)\Mozilla Firefox\latest_en-US\firefox.exe' }
      subject(:latest_esr) { command( "\"#{bin_path}\" --version") }

      it 'is installed' do
        expect(file(bin_path)).to be_file
      end
    end

    control '37.0' do
      let(:bin_path) {'C:\Program Files (x86)\Mozilla Firefox\37.0_en-US\firefox.exe' }
      subject(:specified_version) { command( "\"#{bin_path}\" --version") }

      it 'is installed' do
        expect(file(bin_path)).to be_file
      end

      # This seems to be broken for Windows.
      xit 'is functional when invoked' do
        expect(specified_version.stdout).to match(/Mozilla Firefox 37.0/)
      end

      # This seems to be broken
      xit 'is the correct version of Firefox' do
        expect(specified_version.stdout).to be_version('37.0')
      end
    end
  end
end
