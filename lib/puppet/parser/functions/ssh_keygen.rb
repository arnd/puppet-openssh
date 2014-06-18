# Forked from https://github.com/fup/puppet-ssh @ 59684a8ae174
#
# Takes a Hash of config arguments:
#   Required parameters:
#     :name   (the name of the key - e.g 'my_ssh_key')
#     :request (what type of return value is requested (public, private, auth, known)
#
#   Optional parameters:
#     :type    (the key type - default: 'rsa')
#     :dir     (the subdir of /etc/puppet/ to store the key in - default: 'ssh')
#     :hostkey (weither the key should be a hostkey or not. defines weither to add it to known_hosts or not)
#     :authkey (weither the key is an authkey or not. defines weither to add it to authorized_keys or not)
#
require 'fileutils'
module Puppet::Parser::Functions
  newfunction(:ssh_keygen, :type => :rvalue) do |args|
    unless args.first.class == Hash then
      raise Puppet::ParseError, "ssh_keygen(): config argument must be a Hash"
    end

    config = args.first

    config = {
      'dir'                     => 'ssh',
      'type'                    => 'rsa',
      'hostkey'                 => false,
      'authkey'                 => false,
      'request'                 => nil,
      'comment'                 => nil,
    }.merge(config)

    if config['request'].nil?
        raise Puppet::ParseError, "ssh_keygen(): request argument is required"
    end

    if config['name'].nil? and (request != 'authorized_keys' and request != 'known_hosts)
        raise Puppet::ParseError, "ssh_keygen(): name argument is required"
    end

    # Let comment default to something sensible, unless the user really
    # wants to set it to '' (then we don't stop him)
    if config['comment'].nil?
        hostname = lookupvar('hostname')
        if config['hostkey'] == true
            config['comment'] = hostname
        elsif config['authkey'] == true
            config['comment'] = "root@#{hostname}"
        end
    end


    def init(fullpath)
        if File.exists?(fullpath) and not File.directory?(fullpath)
            raise Puppet::ParseError, "ssh_keygen(): #{fullpath} exists but is not directory"
        end
        if not File.directory?(fullpath)
            debug "creating directory #{fullpath}"
            FileUtils.mkdir_p fullpath
        end
    end

    def create_key_if_not_exists(fullpath, name, comment, type, hostkey, authkey, request)
        begin
            keyfile = "#{fullpath}/#{name}"
            unless File.exists?(keyfile)
                cmdline = "/usr/bin/ssh-keygen -q -t rsa -N '' -C '#{comment}' -f #{keyfile}"
                output = %x[#{cmdline}]
                if $?.exitstatus != 0
                    raise Puppet::ParseError, "calling '#{cmdline}' resulted in error: #{output}"
                end

                if hostkey == true
                    add_key_to_known_hosts(fullpath, name, keyfile)
                end

                if authkey == true
                    add_key_to_authorized_keys(fullpath, name, keyfile)
                end
            else
                debug "ssh_keygen: key already exists. using previously created key in given '#{request}' request"
            end
        rescue => e
            raise Puppet::ParseError, "ssh_keygen(): unable to generate ssh key (#{e})"
        end
    end

    def add_key_to_known_hosts(fullpath, name, keyfile)
        debug "ssh_keygen: adding key #{name} to known_hosts file"

        known_hosts = "#{fullpath}/known_hosts"
        if not File.exists?(known_hosts)
            File.open(known_hosts, 'w') { |f| f.write "# managed by puppet\n" }
        end

        hostname  = lookupvar('hostname')
        fqdn      = lookupvar('fqdn')
        ipaddress = lookupvar('ipaddress')
        key       = get_pubkey(keyfile, false)
    
        cmdline   = "ssh-keygen -q -R #{hostname} -f #{known_hosts}"
        output    = %x[#{cmdline}]
        if $?.exitstatus != 0
            raise Puppet::ParseError, "calling '#{cmdline}' resulted in error: #{output}"
        end

        line = "#{hostname},#{fqdn},#{ipaddress} #{key}"
        File.open(known_hosts, 'a') { |file| file.write(line) }

        debug "ssh_keygen: updated known_hosts file at '#{known_hosts}'"
    end

    def add_key_to_authorized_keys(fullpath, name, keyfile)
        debug "ssh_keygen: adding key #{name} to authorized_keys file"

        authorized_keys = "#{fullpath}/authorized_keys"
        if not File.exists?(authorized_keys)
            File.open(authorized_keys, 'w') { |f| f.write "# managed by puppet\n" }
        end

        key       = get_pubkey(keyfile, false)
    
        line = "#{key}"
        File.open(authorized_keys, 'a') { |file| file.write(line) }

        debug "ssh_keygen: updated authorized_keys file at '#{authorized_keys}'"
    end


    def get_known_hosts(fullpath)
        known_hosts = "#{fullpath}/known_hosts"
        return File.open(known_hosts).read
    end

    def get_authorized_keys(fullpath)
        known_hosts = "#{fullpath}/authorized_keys"
        return File.open(known_hosts).read
    end


    def get_privkey(keyfile)
        begin
            kf = File.open(keyfile).read
            return kf
        rescue => e
            raise Puppet::ParseError, "ssh_keygen(): unable to read private key file: #{e}"
        end
    end

    def get_pubkey(keyfile, only_keypart = false)
        begin
            keyfile = "#{keyfile}.pub"
            pubkey = File.open(keyfile).read
            if only_keypart == true
                pubkey.scan(/^.* (.*) .*$/)[0][0]
            else
                return pubkey
            end 
        rescue => e
            raise Puppet::ParseError, "ssh_keygen: unable to read public key: #{key}"
        end
    end

    # construct fullpath from puppet base and dir argument
    fullpath = "/etc/puppet/#{config['dir']}"

    init(fullpath)
    create_key_if_not_exists(
        fullpath,
        config['name'],
        config['comment'],
        config['type'],
        config['hostkey'],
        config['authkey'],
        config['request']
    ) 

    # Check what mode of action is requested
    begin
        keyfile = "#{fullpath}/#{config['name']}"
        case config['request']
        when "public"
            return get_pubkey(keyfile)
        when "private"
            return get_privkey(keyfile)
        when "known_hosts"
            return get_known_hosts(fullpath)
        when "authorized_keys"
            # TODO: Add a flag for created keys, that they are auth keys
            # TODO: Add a method to create authorized_keys from auth flagged keys
            # TODO: Add a method to return authorized_keys content
            return get_authorized_keys(fullpath)
        end
    rescue => e
        raise Puppet::ParseError, "ssh_keygen(): unable to fulfill request '#{config['request']}': #{e}"
    end
  end
end
