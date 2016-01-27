SOURCES=Config.pm Status.pm Snapshot.pm Features.pm

LXCPROFILEDIR=${DESTDIR}/etc/apparmor.d/lxc

.PHONY: install
install:
	install -d -m 0755 ${PERLDIR}/PVE/API2/LXC
	for i in ${SOURCES}; do install -D -m 0644 $$i ${PERLDIR}/PVE/API2/LXC/$$i; done
	install -dm755 ${LXCPROFILEDIR}
	perl -e 'require "./Features.pm"; PVE::API2::LXC::Features::generate_apparmor_profiles(\*STDOUT);' > ${LXCPROFILEDIR}/lxc-pve-profiles


