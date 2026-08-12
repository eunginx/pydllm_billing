<div align="center">
	<a href="https://ledger.pn.sorsiri.in">
		<img src=".github/pydllm-billing-logo.png" height="80px" width="80px" alt="PYDLLM Billing Logo">
	</a>
	<h2>PYDLLM Billing</h2>
	<p align="center">
		<p>Open Source, modern, and easy-to-use HR and Payroll Software</p>
	</p>

[![CI](https://github.com/eunginx/pydllm_billing/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/eunginx/pydllm_billing/actions/workflows/ci.yml)

<a href="https://trendshift.io/repositories/10972" target="_blank"><img src="https://trendshift.io/api/badge/repositories/10972" alt="frappe%2Fhrms | Trendshift" style="width: 250px; height: 55px;" width="250" height="55"/></a>
</div>

<div align="center">
	<img src=".github/hrms-hero.png"/>
</div>

<div align="center">
	<a href="https://frappe.io/hr">Website</a>
	-
	<a href="https://docs.frappe.io/hr/introduction">Documentation</a>
</div>

## PYDLLM Billing

This repository hosts the production deployment of Frappe HR for **ledger.pn.sorsiri.in**, built from the upstream Frappe HR source.

## Production Deployment

The production stack is orchestrated with Docker Compose and served behind nginx. Deployment is triggered automatically on pushes to the `main` branch via GitHub Actions.

```sh
git clone https://github.com/eunginx/pydllm_billing.git
cd pydllm_billing
cp .env.example .env
# edit .env and set strong passwords + SSL certificates in docker/nginx/ssl/
docker compose -f docker/docker-compose.prod.yml up -d --build
```

Required before first deploy:
- Place TLS certificate at `docker/nginx/ssl/fullchain.pem`
- Place TLS key at `docker/nginx/ssl/privkey.pem`
- DNS `ledger.pn.sorsiri.in` pointing to the host running Docker.

## Motivation
This project started from the upstream Frappe HR product and is configured for the PYDLLM Billing organisation.

## Key Features

- **Employee Lifecycle**: From onboarding employees, managing promotions and transfers, all the way to documenting feedback with exit interviews, make life easier for employees throughout their life cycle.
- **Leave and Attendance**: Configure leave policies, pull regional holidays with a click, check-in and check-out with geolocation capturing, track leave balances and attendance with reports.
- **Expense Claims and Advances**: Manage employee advances, claim expenses, configure multi-level approval workflows, all this with seamless integration with ERPNext accounting.
- **Performance Management**: Track goals, align goals with key result areas (KRAs), enable employees to evaluate themselves, make managing appraisal cycles easy.
- **Payroll & Taxation**: Create salary structures, configure income tax slabs, run standard payroll, accommodate additional salaries and off cycle payments, view income breakup on salary slips and so much more.
- **Frappe HR Mobile App**: Apply for and approve leaves on the go, check-in and check-out, access employee profile right from the mobile app.

<details open>

<summary>View Screenshots</summary>
	<img src=".github/hrms-appraisal.png"/>
	<img src=".github/hrms-requisition.png"/>
	<img src=".github/hrms-attendance.png"/>
	<img src=".github/hrms-salary.png"/>
	<img src=".github/hrms-pwa.png"/>
</details>

### Under the Hood

- [**Frappe Framework**](https://github.com/frappe/frappe): A full-stack web application framework written in Python and Javascript. The framework provides a robust foundation for building web applications, including a database abstraction layer, user authentication, and a REST API.

- [**Frappe UI**](https://github.com/frappe/frappe-ui): A Vue-based UI library, to provide a modern user interface. The Frappe UI library provides a variety of components that can be used to build single-page applications on top of the Frappe Framework.

## Production Setup

### Reverse Proxy

Nginx is included in the production compose. It terminates TLS and proxies to the Frappe backend on port `8000` and the Socket.IO server on port `9000`. See [docker/nginx/nginx.conf](docker/nginx/nginx.conf).

| Setting | Value |
|---|---|
| Public domain | `ledger.pn.sorsiri.in` |
| Upstream host | `backend:8000` / `backend:9000` |
| Public ports | `80` and `443` |


## Development setup
### Docker
For local development, use the original development compose:
```
git clone https://github.com/eunginx/pydllm_billing.git
cd pydllm_billing/docker
docker-compose up
```

Wait for some time until the setup script creates the site. After that you can access `http://ledger.pn.sorsiri.in:8000` in your browser and the login screen for HR should show up.

Use the following credentials to log in:

- Username: `Administrator`
- Password: `admin`

### Local

1. Set up bench by following the [Installation Steps](https://frappeframework.com/docs/user/en/installation) and start the server and keep it running
	```sh
	$ bench start
	```
2. In a separate terminal window, run the following commands
	```sh
	$ bench new-site ledger.pn.sorsiri.in
	$ bench get-app erpnext
	$ bench get-app hrms
	$ bench --site ledger.pn.sorsiri.in install-app hrms
	$ bench --site ledger.pn.sorsiri.in add-to-hosts
	```
3. You can access the site at `http://ledger.pn.sorsiri.in:8080`

## Learning and Community

1. [Frappe School](https://frappe.school) - Learn Frappe Framework and ERPNext from the various courses by the maintainers or from the community.
2. [Documentation](https://docs.frappe.io/hr) - Extensive documentation for Frappe HR.
3. [User Forum](https://discuss.erpnext.com/) - Engage with the community of ERPNext users and service providers.
4. [Telegram Group](https://t.me/frappehr) - Get instant help from the community of users.


## Contributing

1. [Issue Guidelines](https://github.com/frappe/erpnext/wiki/Issue-Guidelines)
1. [Report Security Vulnerabilities](https://erpnext.com/security)
1. [Pull Request Requirements](https://github.com/frappe/erpnext/wiki/Contribution-Guidelines)


## Logo and Trademark Policy

Please read our [Logo and Trademark Policy](TRADEMARK_POLICY.md).

<br />
<br />
<div align="center" style="padding-top: 0.75rem;">
	<a href="https://frappe.io" target="_blank">
		<picture>
			<source media="(prefers-color-scheme: dark)" srcset="https://frappe.io/files/Frappe-white.png">
			<img src="https://frappe.io/files/Frappe-black.png" alt="Frappe Technologies" height="28"/>
		</picture>
	</a>
</div>

