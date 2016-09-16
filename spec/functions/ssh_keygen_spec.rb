require 'spec_helper'

require 'fileutils'
require 'sshkey'

describe 'ssh_keygen' do
    before :all do
        @tempdir = Dir.mktmpdir("rspec-")
    end

    after :all do
         FileUtils.rm_r(@tempdir)
    end

    let (:tempdir) { @tempdir }

    context "test for expected exceptions" do
        it "raises expected error with no arguments" do
            should run.with_params().and_raise_error(Puppet::ParseError, /argument must be a Hash/)
        end
    end

    context "with params for a hostkey" do
        let(:subdir)  { 'ssh/hostkeys' }
        let(:keypath) { File.join(tempdir, subdir) }
        let(:keyname) { "host1.example.com" }

        let(:base_params) {{
            'hostkey'     => true,
            'hostaliases' => [],
            'type'        => 'rsa',
            'basedir'     => "#{tempdir}",
            'dir'         => subdir,
            'name'        => keyname,
            'comment'     => keyname,
        }}

        let(:params) { base_params.merge({
            'request'     => 'private',
        })}

        it { is_expected.to run.with_params(params) }

        it "creates a file for the host private key" do
            expect(File).to exist("#{keypath}/#{params['name']}")
        end
        it "creates a file for the host public key" do
            expect(File).to exist("#{keypath}/#{params['name']}.pub")
        end

        it "creates known hosts file" do
            path = "#{tempdir}/ssh/hostkeys/known_hosts"
            expect(File).to exist("#{tempdir}/ssh/hostkeys/known_hosts")
        end

        it "returns the same key on a subsequent run" do
            key1 = subject.call([params])
            key2 = subject.call([params])
            expect(key1).to eq(key2)
        end

        it "has public key in authorized_keys" do
            public_key  = File.read("#{keypath}/#{params['name']}.pub");
            known_hosts = File.read("#{tempdir}/ssh/hostkeys/known_hosts")

            expect(known_hosts).to include(public_key)
        end

        context "when requesting public key" do
            let (:params)       { base_params.merge( { 'request' => 'public' } ) }
            let (:key)          { subject.call([params]) }
            let (:key_object)   { SSHKey.new(key) }

            it "returns a valid ssh public key" do
                expect(SSHKey.valid_ssh_public_key?(key)).to be_truthy
            end
        end
    end
end
