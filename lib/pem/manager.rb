require 'pathname'
require 'spaceship'

module PEM
  # Creates the push profile and stores it in the correct location
  class Manager
    class << self
      def start
        FastlaneCore::PrintTable.print_values(config: PEM.config, hide_keys: [], title: "Summary for PEM #{PEM::VERSION}")
        login

        existing_certificate = certificate.all.detect do |c|
          c.name == PEM.config[:app_identifier]
        end

        if existing_certificate
          remaining_days = (existing_certificate.expires - Time.now) / 60 / 60 / 24
          Helper.log.info "Existing push notification profile '#{existing_certificate.owner_name}' is valid for #{remaining_days.round} more days."
          if remaining_days > 30
            if PEM.config[:force]
              Helper.log.info "You already have an existing push certificate, but a new one will be created since the --force option has been set.".green
            else
              Helper.log.info "You already have a push certificate, which is active for more than 30 more days. No need to create a new one".green
              Helper.log.info "If you still want to create a new one, use the --force option when running PEM.".green
              return false
            end
          end
        end

        return create_certificate
      end

      def login
        Helper.log.info "Starting login with user '#{PEM.config[:username]}'"
        Spaceship.login(PEM.config[:username], nil)
        Spaceship.client.select_team
        Helper.log.info "Successfully logged in"
      end

      # rubocop:disable Metrics/AbcSize
      def create_certificate
        Helper.log.warn "Creating a new push certificate for app '#{PEM.config[:app_identifier]}'."

        csr, pkey = Spaceship.certificate.create_certificate_signing_request

        begin
          cert = certificate.create!(csr: csr, bundle_id: PEM.config[:app_identifier])
        rescue => ex
          if ex.to_s.include? "You already have a current"
            # That's the most common failure probably
            Helper.log.info ex.to_s
            Helper.log.error "You already have 2 active push profiles for this application/environment.".red
            Helper.log.error "You'll need to revoke an old certificate to make room for a new one".red
          else
            raise ex
          end
        end

        x509_certificate = cert.download
        certificate_type = (PEM.config[:development] ? 'development' : 'production')
        filename_base = PEM.config[:pem_name] || "#{certificate_type}_#{PEM.config[:app_identifier]}"
        filename_base = File.basename(filename_base, ".pem") # strip off the .pem if it was provided.

        if PEM.config[:save_private_key]
          private_key_path = File.join(PEM.config[:output_path], "#{filename_base}.pkey")
          File.write(private_key_path, pkey.to_pem)
          Helper.log.info "Private key: ".green + Pathname.new(private_key_path).realpath.to_s
        end

        if PEM.config[:generate_p12]
          p12_cert_path = File.join(PEM.config[:output_path], "#{filename_base}.p12")
          p12 = OpenSSL::PKCS12.create(PEM.config[:p12_password], certificate_type, pkey, x509_certificate)
          File.write(p12_cert_path, p12.to_der)
          Helper.log.info "p12 certificate: ".green + Pathname.new(p12_cert_path).realpath.to_s
        end

        x509_cert_path = File.join(PEM.config[:output_path], "#{filename_base}.pem")
        File.write(x509_cert_path, x509_certificate.to_pem + pkey.to_pem)
        Helper.log.info "PEM: ".green + Pathname.new(x509_cert_path).realpath.to_s
        return x509_cert_path
      end
      # rubocop:enable Metrics/AbcSize

      def certificate
        if PEM.config[:development]
          Spaceship.certificate.development_push
        else
          Spaceship.certificate.production_push
        end
      end
    end
  end
end
