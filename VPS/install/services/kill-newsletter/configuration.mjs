export default {
  hostname: process.env.KILL_NEWSLETTER_HOSTNAME ?? "localhost",
  systemAdministratorEmail:
    process.env.KILL_NEWSLETTER_ADMIN_EMAIL ?? "local@example.invalid",
  tls: {
    key: "/tmp/unused-tls-key",
    certificate: "/tmp/unused-tls-certificate",
  },
  dataDirectory: "/app/data",
  environment: process.env.NODE_ENV ?? "production",
};
