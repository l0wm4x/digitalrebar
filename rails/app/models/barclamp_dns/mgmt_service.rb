# Copyright 2015, Greg Althaus
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

require 'rest-client'

class BarclampDns::MgmtService < Service

  def template
    # this is a workable solution for now, we use the admin node to determine domain (except when non-exists!)
    domain = Node.admin.first.name.split(".",2)[1] rescue I18n.t('not_set')
    {"crowbar" => {     "dns" => {
        "domain" => domain,
        "contact" => "support@localhost.localdomain",
        "forwarders" =>  [],
        "static" => {},
        "ttl" => "1h",
        "slave_refresh" => "1d",
        "slave_retry" => "2h",
        "slave_expire" => "4w",
        "negative_cache" => 300}}}
  end

  def do_transition(nr,data)
    internal_do_transition(nr, data, "dns-mgmt-service", "dns-management-servers") do |s|
      Rails.logger.debug("DnsMgmtServer: #{s.inspect} #{s.ServiceAddress}")
      addr = IP.coerce(s.ServiceAddress)
      Rails.logger.debug("DnsMgmtServer: #{addr.inspect}")

      server_name = s.ServiceTags.first
      cert_pem = ConsulAccess.getKey("opencrowbar/private/dns-mgmt/#{server_name}/cert_pem")
      access_name = ConsulAccess.getKey("opencrowbar/private/dns-mgmt/#{server_name}/access_name")
      access_password = ConsulAccess.getKey("opencrowbar/private/dns-mgmt/#{server_name}/access_password")

      url = "https://#{access_name}:#{access_password}@"
      if addr.v6?
        url << "[#{addr.addr}]"
      else
        url << addr.addr
      end
      url << ":#{s.ServicePort}"

      { "address" => s.ServiceAddress,
        "port" => "#{s.ServicePort}",
        "name" => server_name,
        "cert" => cert_pem,
        "access_name" => access_name,
        "access_password" => access_password,
        "url" => url}
    end
  end

  def on_active(nr)
    # Preset all the pre-existing allocations.

    services = Attrib.get('dns-management-servers', nr)
    slist = []
    shash = {}
    addrs = {}
    services.each do |s|
      svc = s['name']
      slist << svc
      shash[svc] = s
      addrs[svc] = []
    end

    NetworkAllocation.all.each do |na|
      Rails.logger.fatal("GREG: na = #{na}")
      svc = na.network_range.dns_svc_name
      Rails.logger.fatal("GREG: testing #{na.address} for #{svc} in #{slist}")
      Rails.logger.fatal("GREG: testing #{na.network_range.update_dns}")
      addrs[svc] << na if !svc.nil? and slist.include?(svc) and na.network_range.update_dns
    end

    Rails.logger.fatal("GREG: setting initial values")

    shash.each do |sname, service|
      Rails.logger.fatal("GREG: #{sname} is being updated")
      addrs[sname].each do |na|
        rrtype = (na.address.v4? ? 'A' : 'AAAA')
        Rails.logger.fatal("GREG: #{sname} #{rrtype}")
        replace_dns_record(service, na.network_range.dns_domain, rrtype, get_name(na.node), na.address.addr, true)
      end
    end

    Rails.logger.fatal("GREG: Done updating")
  end

  def on_node_change(n)
    if n.previous_changes[:name]
      Rails.logger.fatal("GREG: name of node changed, #{n.name} update dns A/AAAA records")
      NetworkAllocation.node(n).each do |na|
        update_mapping(n, na.network_range, na.address)
      end
    end
  end

  def on_network_allocation_create(na)
    update_mapping(na.node, na.network_range, na.address)
  end

  def on_network_allocation_delete(na)
    delete_mapping(na.node, na.network_range, na.address)
  end

  def delete_mapping(node, range, address)
    Rails.logger.fatal("GREG: #{node.name} #{address} is being removed.")

    return unless range.update_dns
    service = get_service(range.dns_svc_name)
    return unless service

    rrtype = (address.v4? ? 'A' : 'AAAA')
    remove_dns_record(service, range.dns_domain, rrtype, get_name(node), true)
  end

  def update_mapping(node, range, address)
    Rails.logger.fatal("GREG: #{node.name} #{address} is being added.")

    return unless range.update_dns
    service = get_service(range.dns_svc_name)
    return unless service

    rrtype = (address.v4? ? 'A' : 'AAAA')
    replace_dns_record(service, range.dns_domain, rrtype, get_name(node), address.addr, true)
  end

  # GREG: This is busted - hostname_template needs to live somewhere
  def get_name(node)
    name = node.name.split('.')[0]
    return name unless hostname_template
    hostname_template.gsub('{{node.name}}', name)
  end

  def get_service(service_name)
    service = nil
    # This is not cool, but should be small in most environments.
    BarclampDns::MgmtService.all.each do |role|
      role.node_roles.each do |nr|
        services = Attrib.get('dns-management-servers', nr)
        next unless services
        services.each do |s|
          service = s if s['name'] == service_name
          return service if service
        end
      end
    end
    nil
  end

  def send_request(url, data, ca_string)
    store = OpenSSL::X509::Store.new
    store.add_cert(OpenSSL::X509::Certificate.new(ca_string))
    
    RestClient::Resource.new(
        url,
        :ssl_cert_store =>  store,
        :verify_ssl     =>  OpenSSL::SSL::VERIFY_PEER
    ).patch data.to_json, :content_type => :json, :accept => :json
  end

  def replace_dns_record(service, zone, rrtype, name, value, setptr)
    Rails.logger.fatal("GREG: replace_dns_record: #{service['name']} #{zone} #{rrtype} #{name} #{value} #{setptr}")

    url = "#{service['url']}/zones/#{zone}"

    data = {
        'rrsets' => [
            {
                'name' => name,
                'type' => rrtype,
                'changetype' => 'REPLACE',
                'records' => [
                    {
                        'content' => value,
                        'disabled' => false,
                        'name' => name,
                        'ttl' => 3600,
                        'type' => rrtype,
                        'setptr' => setptr,
                        'priority' => 0
                    }
                ]
            }
        ]
    }

    Rails.logger.fatal("GREG: replace dns record: #{url}")

    send_request(url, data, service['cert'])
  end

  def remove_dns_record(service, zone, rrtype, name, setptr)
    Rails.logger.fatal("GREG: remove_dns_record: #{service['name']} #{zone} #{rrtype} #{name} #{setptr}")

    url = "#{service['url']}/zones/#{zone}"
    data = {
        'rrsets' => [
            {
                'name' => name,
                'type' => rrtype,
                'changetype' => 'DELETE',
                'records' => [ ]
            }
        ]
    }

    send_request(url, data, service['cert'])
  end

end
