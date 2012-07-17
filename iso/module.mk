
/:=$(BUILD_DIR)/iso/

.PHONY: iso
all: iso
iso: $/nailgun-ubuntu-12.04-amd64.iso

clean: $/umount_ubuntu_image $/umount_centos_image

.PHONY: $/umount_ubuntu_image
$/umount_ubuntu_image:
	-fusermount -u $(BUILD_DIR)/ubuntu

.PHONY: $/umount_centos_image
$/umount_centos_image:
	-fusermount -u $(BUILD_DIR)/centos

ifndef BINARIES_DIR
$/%:
	$(error BINARIES_DIR variable is not defined)
else

APT-GET:=apt-get

$(call assert-variable,gnupg.home)

find-files=$(shell test -d $1 && cd $1 && find * -type f 2> /dev/null)

EXTRA_PACKAGES:=$(shell grep -v ^\\s*\# requirements-deb.txt)
CACHED_EXTRA_PACKAGES:=$(shell cd $(BINARIES_DIR)/ubuntu/precise/extra && ls *.deb)

CENTOSEXTRA_PACKAGES:=$(shell grep -v ^\\s*\# requirements-rpm.txt)

ISOROOT:=$/isoroot
ISO_IMAGE:=$(BINARIES_DIR)/ubuntu-12.04-server-amd64.iso
ISO_RELEASE:=precise
ISO_VERSION:=12.04
ISO_ARCHS:=i386 amd64
ISO_SECTIONS:=main restricted universe multiverse

CENTOSISO:=$(BINARIES_DIR)/CentOS-6.2-x86_64-minimal.iso
CENTOSMAJOR:=6
CENTOSRELEASE:=6.2
CENTOSARCH:=x86_64
CENTOSMIRROR:=http://mirror.yandex.ru/centos

UBUNTU_MIRROR:=http://ru.archive.ubuntu.com/ubuntu
OPSCODE_UBUNTU_MIRROR:=http://apt.opscode.com
UBUNTU_GPG_KEY1:=FBB75451 
UBUNTU_GPG_KEY2:=437D05B5 

$/%: /:=$/
$/%: ISOROOT:=$(ISOROOT)
$/%: ISO_RELEASE:=$(ISO_RELEASE)
$/%: ISO_VERSION:=$(ISO_VERSION)


$(BUILD_DIR)/ubuntu: $(BUILD_DIR)/ubuntu/md5sum.txt
$(BUILD_DIR)/ubuntu/%:
	mkdir -p $(@D)
	fuseiso $(ISO_IMAGE) $(@D)

$(BUILD_DIR)/centos: | $(BUILD_DIR)/centos/Packages
$(BUILD_DIR)/centos/%:
	mkdir -p $(@D)
	fuseiso $(CENTOSISO) $(@D)

# DEBIAN PACKET CACHE RULES

APT_ROOT=$(abspath $/apt)

define apt_conf_contents
APT
{
  Architecture "amd64";
  Default-Release "$(ISO_RELEASE)";
  Get::AllowUnauthenticated "true";
};

Dir
{
  State "$(APT_ROOT)/state";
  State::status "status";
  Cache::archives "$(APT_ROOT)/archives";
  Cache "$(APT_ROOT)/cache";
  Etc "$(APT_ROOT)/etc";
};
endef

$/apt/etc/apt.conf: export contents:=$(apt_conf_contents)
$/apt/etc/apt.conf: | $/apt/etc/.dir
	@mkdir -p $(@D)
	echo "$${contents}" > $@


define apt_sources_list_contents
deb $(UBUNTU_MIRROR) precise main restricted universe multiverse
deb-src $(UBUNTU_MIRROR) precise main restricted universe multiverse
deb $(OPSCODE_UBUNTU_MIRROR) $(ISO_RELEASE)-0.10 main
endef

$/apt/etc/sources.list: export contents:=$(apt_sources_list_contents)
$/apt/etc/sources.list: | $/apt/etc/.dir
	@mkdir -p $(@D)
	echo "$${contents}" > $@


define opscode_preferences_contents
Package: *
Pin: origin "apt.opscode.com"
Pin-Priority: 999
endef

$/apt/etc/preferences.d/opscode: export contents:=$(opscode_preferences_contents)
$/apt/etc/preferences.d/opscode: | $/apt/etc/preferences.d/.dir
	@mkdir -p $(@D)
	echo "$${contents}" > $@


$/apt/state/status: | $/apt/state/.dir
	$(ACTION.TOUCH)

$/apt-cache-infra.done: \
	  $/apt/etc/apt.conf \
		$/apt/etc/sources.list \
		$/apt/etc/preferences.d/opscode \
	  $/apt/archives/.dir \
		| $/apt/cache/.dir \
		  $/apt/state/status
	$(ACTION.TOUCH)

$/apt-cache-iso.done: $(ISO_IMAGE) | $(BUILD_DIR)/ubuntu/pool $/apt/archives/.dir
	find $(abspath $(BUILD_DIR)/ubuntu/pool) -type f \( -name '*.deb' -o -name '*.udeb' \) -exec ln -sf {} $/apt/archives \;
	$(ACTION.TOUCH)

$/apt-cache-index.done: \
	  $/apt-cache-infra.done \
	  $(addprefix $/apt/state/,$(call find-files,$(BINARIES_DIR)/ubuntu/precise/state))
	$(APT-GET) -c=$/apt/etc/apt.conf update
	$(ACTION.TOUCH)

$/apt-cache-extra.done: \
	  $/apt-cache-index.done \
		$/apt-cache-iso.done \
		$(addprefix $/apt/archives/,$(call find-files,$(BINARIES_DIR)/ubuntu/$(ISO_RELEASE)/extra)) \
		requirements-deb.txt
	for p in $(EXTRA_PACKAGES); do \
	$(APT-GET) -c=$/apt/etc/apt.conf -d -y install $$p; \
	done
	$(ACTION.TOUCH)

$/apt/archives/%.deb: $(BINARIES_DIR)/ubuntu/$(ISO_RELEASE)/extra/%.deb
	ln -sf $(abspath $<) $@

$/apt-cache.done: $/apt-cache-extra.done
	$(ACTION.TOUCH)


# UBUNTU KEYRING RULES

$/ubuntu-mirantis-gnupg/%: $(gnupg.home)/%
	$(ACTION.COPY)
	chmod 600 $@

$/ubuntu-mirantis-gnupg/.done: \
	  $/debian/ubuntu-keyring/keyrings/ubuntu-archive-keyring.gpg \
		$/ubuntu-mirantis-gnupg/pubring.gpg \
		$/ubuntu-mirantis-gnupg/secring.gpg
	chmod 700 $(@D)
	GNUPGHOME=$/ubuntu-mirantis-gnupg gpg --import < $<
	GNUPGHOME=$/ubuntu-mirantis-gnupg gpg --yes --export --output $< $(UBUNTU_GPG_KEY1) $(UBUNTU_GPG_KEY2) $(gnupg.default-key-id)
	$(ACTION.TOUCH)

$/debian/ubuntu-keyring/keyrings/ubuntu-archive-keyring.gpg: $(BINARIES_DIR)/ubuntu/precise/ubuntu-keyring.tar.gz
	rm -rf $/debian/ubuntu-keyring
	mkdir -p $/debian/ubuntu-keyring
	tar -xf $< --strip-components=1 -C $/debian/ubuntu-keyring
	find $/debian/ubuntu-keyring/ -type f -exec touch {} \;

$/debian/ubuntu-keyring/.done: $/debian/ubuntu-keyring/keyrings/ubuntu-archive-keyring.gpg $/ubuntu-mirantis-gnupg/.done
	cd $/debian/ubuntu-keyring && \
		dpkg-buildpackage -b -m"Mirantis Nailgun" -k"$(gnupg.default-key-id)" -uc -us
	$(ACTION.TOUCH)

# RPM PACKAGE CACHE RULES

define yum_conf
[main]
cachedir=$/rpm/cache
keepcache=0
debuglevel=6
logfile=$/rpm/yum.log
exactarch=1
obsoletes=1
gpgcheck=0
plugins=0
reposdir=$/rpm/etc/yum.repos.d
endef

$/rpm/etc/yum.conf: export contents:=$(yum_conf)
$/rpm/etc/yum.conf: | $/rpm/etc/.dir
	@mkdir -p $(@D)
	echo "$${contents}" > $@

define yum_base_repo
[base]
name=CentOS $(CENTOSRELEASE) - Base
baseurl=$(CENTOSMIRROR)/$(CENTOSRELEASE)/os/$(CENTOSARCH)
gpgcheck=0
enabled=1

[updates]
name=CentOS $(CENTOSRELEASE) - Updates
baseurl=$(CENTOSMIRROR)/$(CENTOSRELEASE)/updates/$(CENTOSARCH)
gpgcheck=0
enabled=1

[extras]
name=CentOS $(CENTOSRELEASE) - Extras
baseurl=$(CENTOSMIRROR)/$(CENTOSRELEASE)/extras/$(CENTOSARCH)
gpgcheck=0
enabled=1

[centosplus]
name=CentOS $(CENTOSRELEASE) - Plus
baseurl=$(CENTOSMIRROR)/$(CENTOSRELEASE)/centosplus/$(CENTOSARCH)
gpgcheck=0
enabled=1

[contrib]
name=CentOS $(CENTOSRELEASE) - Contrib
baseurl=$(CENTOSMIRROR)/$(CENTOSRELEASE)/contrib/$(CENTOSARCH)
gpgcheck=0
enabled=1

[epel]
name=Extra Packages for Enterprise Linux 6
baseurl=http://download.fedoraproject.org/pub/epel/$(CENTOSMAJOR)/$(CENTOSARCH)
enabled=1
gpgcheck=0

[mirantis]
name=Mirantis Packages for CentOS
baseurl=http://moc-ci.srt.mirantis.net/rpm
enabled=1
gpgcheck=0
endef

$/rpm/etc/yum.repos.d/base.repo: export contents:=$(yum_base_repo)
$/rpm/etc/yum.repos.d/base.repo: | $/rpm/etc/yum.repos.d/.dir
	@mkdir -p $(@D)
	echo "$${contents}" > $@

$/rpm/comps.xml: $(BINARIES_DIR)/centos/$(CENTOSRELEASE)/comps.xml
	$(ACTION.COPY)

$/rpm-groups.done: $/rpm/comps.xml
	$(ACTION.TOUCH)

$/rpm-cache-infra.done: \
	  $/rpm/etc/yum.conf \
	  $/rpm/etc/yum.repos.d/base.repo
	$(ACTION.TOUCH)

$/rpm-cache-iso.done: $(CENTOSISO) | $(BUILD_DIR)/centos/Packages $/rpm/Packages/.dir
	find $(abspath $(BUILD_DIR)/centos/Packages) -type f \( -name '*.rpm' \) -exec ln -sf {} $/rpm/Packages \;
	$(ACTION.TOUCH)

$/rpm-cache-extra.done: \
	  $/rpm-cache-infra.done \
	  $/rpm-cache-iso.done \
	  $(addprefix $/rpm/Packages/,$(call find-files,$(BINARIES_DIR)/centos/$(CENTOSRELEASE)/Packages)) \
	  requirements-rpm.txt
	for p in $(CENTOSEXTRA_PACKAGES); do \
	repotrack -c $/rpm/etc/yum.conf -p $/rpm/Packages -a $(CENTOSARCH) $$p; \
	done
	$(ACTION.TOUCH)

$/rpm/Packages/%.rpm: $(BINARIES_DIR)/centos/$(CENTOSRELEASE)/Packages/%.rpm
	ln -sf $(abspath $<) $@

$/rpm-cache.done: $/rpm-cache-extra.done
	$(ACTION.TOUCH)

# ISO ROOT RULES

$/isoroot-infra.done: $(ISO_IMAGE) | $(BUILD_DIR)/ubuntu
	mkdir -p $(ISOROOT)
	rsync --recursive --links --perms --chmod=u+w --exclude=pool $(BUILD_DIR)/ubuntu/ $(ISOROOT)
	$(ACTION.TOUCH)

$/isoroot-pool.done: $/apt-cache.done
	mkdir -p $(ISOROOT)/pools/$(ISO_RELEASE)
	find $/apt/archives \( -name '*.deb' -o -name '*.udeb' \) | while read debfile; do \
    packname=`basename $${debfile} | cut -d_ -f1` ; \
    section=`grep -l "^$${packname}\s" $(BINARIES_DIR)/ubuntu/$(ISO_RELEASE)/indices/* | \
	    grep -v extra | head -1 | cut -d. -f3` ; \
    test -z $${section} && section=main ; \
    mkdir -p $(ISOROOT)/pools/$(ISO_RELEASE)/$${section} ; \
    cp -n $${debfile} $(ISOROOT)/pools/$(ISO_RELEASE)/$${section}/ ; \
  done
	$(ACTION.TOUCH)

$/isoroot-rpm.done: $/rpm-cache.done $/rpm-groups.done
	mkdir -p $(ISOROOT)/centos/$(CENTOSRELEASE)
	find $/rpm/Packages -name '*.rpm' | while read rpmfile; do \
	cp -n $${rpmfile} $(ISOROOT)/centos/$(CENTOSRELEASE)/ ; \
	done
	createrepo -g `readlink -f "$/rpm/comps.xml"` -o $(ISOROOT)/centos/$(CENTOSRELEASE) $(ISOROOT)/centos/$(CENTOSRELEASE)
	$(ACTION.TOUCH)

$/isoroot-keyring.done: $/isoroot-pool.done $/debian/ubuntu-keyring/.done
	rm -rf $(ISOROOT)/pools/$(ISO_RELEASE)/main/ubuntu-keyring*deb
	cp $/debian/ubuntu-keyring*deb $(ISOROOT)/pools/$(ISO_RELEASE)/main/
	$(ACTION.TOUCH)

$/isoroot-packages.done: $/isoroot-pool.done $/isoroot-keyring.done
	$(ACTION.TOUCH)

$/isoroot-isolinux.done: $/isoroot-infra.done $(addprefix iso/stage/,$(call find-files,iso/stage))
	rsync -a iso/stage/ $(ISOROOT)
	$(ACTION.TOUCH)

$/isoroot.done: \
	  $/isoroot-infra.done \
	  $/isoroot-packages.done \
	  $/isoroot-rpm.done \
		$/isoroot-isolinux.done \
		$(ISOROOT)/bootstrap/linux \
		$(ISOROOT)/bootstrap/initrd.gz \
		$(ISOROOT)/bootstrap/bootstrap.rsa \
		$(addprefix $(ISOROOT)/netinst/,$(call find-files,$(BINARIES_DIR)/netinst)) \
		$(ISOROOT)/bin/late \
		$(ISOROOT)/gnupg \
		$(addprefix $(ISOROOT)/gnupg/,$(call find-files,gnupg)) \
		$(ISOROOT)/sync \
		$(addprefix $(ISOROOT)/sync/,$(call find-files,iso/sync)) \
		$(addprefix $(ISOROOT)/indices/,$(call find-files,$(BINARIES_DIR)/ubuntu/$(ISO_RELEASE)/indices)) \
		$(addprefix $(ISOROOT)/nailgun/,$(call find-files,nailgun)) \
		$(addprefix $(ISOROOT)/nailgun/bin/,create_release install_cookbook deploy agent) \
		$(addprefix $(ISOROOT)/nailgun/solo/,solo.rb solo.json) \
		$(addprefix $(ISOROOT)/nailgun/cookbooks/,$(call find-files,cookbooks)) \
		$(addprefix $(ISOROOT)/nailgun/os-cookbooks/,$(call find-files,cooks)) \
		$/isoroot-gems.done \
		$(ISOROOT)/eggs \
		$(addprefix $(ISOROOT)/eggs/,$(call find-files,$(BINARIES_DIR)/eggs)) \
		$(ISOROOT)/dists/$(ISO_RELEASE)/Release \
		$(ISOROOT)/dists/$(ISO_RELEASE)/Release.gpg
	$(ACTION.TOUCH)

$(ISOROOT)/md5sum.txt: $/isoroot.done
	cd $(@D) && find * -type f -print0 | \
	  xargs -0 md5sum | \
		grep -v "boot.cat" | \
		grep -v "md5sum.txt" > $(@F)

# Arguments:
#   1 - section (e.g. main, restricted, etc.)
#   2 - arch (e.g. i386, amd64)
#   3 - override path
#   4 - extra override path
define packages-build-rule-template
$(ISOROOT)/dists/$(ISO_RELEASE)/$1/binary-$2/Packages: \
	  $/isoroot-packages.done \
		$(ISOROOT)/pools/$(ISO_RELEASE)/$1 \
		$3 \
		$4
	mkdir -p $$(@D)
	cd $(ISOROOT) && \
		dpkg-scanpackages --multiversion --arch $2 --type deb \
			--extra-override $(abspath $4) pools/$(ISO_RELEASE)/$1 $(abspath $3) > $$(abspath $$@)

$(ISOROOT)/dists/$(ISO_RELEASE)/$1/debian-installer/binary-$2/Packages: \
	  $/isoroot-packages.done \
		$(ISOROOT)/pools/$(ISO_RELEASE)/$1 \
		$3.debian-installer \
		$4
	mkdir -p $$(@D)
	cd $(ISOROOT) && \
		dpkg-scanpackages --multiversion --arch $2 --type udeb \
			--extra-override $(abspath $4) pools/$(ISO_RELEASE)/$1 $(abspath $3.debian-installer) > $$(abspath $$@)
endef

packages-build-rule = $(eval $(call packages-build-rule-template,$1,$2,$3,$4))

# Generate rules for building Packages index for all supported architectures
#
# NOTE: section=main -- special case
INDICES_DIR:=$(BINARIES_DIR)/ubuntu/$(ISO_RELEASE)/indices

$(foreach section,$(filter-out main,$(ISO_SECTIONS)),\
	$(foreach arch,$(ISO_ARCHS),\
    $(call packages-build-rule,$(section),$(arch),\
      $(INDICES_DIR)/override.$(ISO_RELEASE).$(section),\
			$(INDICES_DIR)/override.$(ISO_RELEASE).extra.$(section))))

$(foreach arch,$(ISO_ARCHS),\
	$(call packages-build-rule,main,$(arch),\
	  $(INDICES_DIR)/override.$(ISO_RELEASE).main,\
		$/override.$(ISO_RELEASE).extra.main))

$/override.$(ISO_RELEASE).extra.main: \
	  $(INDICES_DIR)/override.$(ISO_RELEASE).extra.main \
		$(BUILD_DIR)/ubuntu/dists/$(ISO_RELEASE)/main/binary-amd64/Packages.gz
	$(ACTION.COPY)
	gunzip -c $(filter %/Packages.gz,$^) | awk -F ": *" '$$1=="Package" {package=$$2} $$1=="Task" {print package " Task " $$2}' >> $@

# Arguments:
#   1 - section (e.g. main, restricted, etc.)
#   2 - arch
define release-build-rule-template
$(ISOROOT)/dists/$(ISO_RELEASE)/$1/binary-$2/Release:
	@mkdir -p $$(@D)
	echo "Archive: $(ISO_RELEASE)\nVersion: $(ISO_VERSION)\nComponent: $1\nOrigin: Mirantis\nLabel: Mirantis\nArchitecture: $2" > $$@
endef

release-build-rule = $(eval $(call release-build-rule-template,$1,$2))

$(foreach section,$(ISO_SECTIONS),\
  $(foreach arch,$(ISO_ARCHS),\
    $(call release-build-rule,$(section),$(arch))))


define release_conf_contents
APT::FTPArchive::Release::Origin "Mirantis";
APT::FTPArchive::Release::Label "Mirantis";
APT::FTPArchive::Release::Suite "$(ISO_RELEASE)";
APT::FTPArchive::Release::Version "$(ISO_VERSION)";
APT::FTPArchive::Release::Codename "$(ISO_RELEASE)";
APT::FTPArchive::Release::Architectures "$(ISO_ARCHS)";
APT::FTPArchive::Release::Components "$(ISO_SECTIONS)";
APT::FTPArchive::Release::Description "Mirantis Nailgun Repo";
endef

$/release.conf: export contents:=$(release_conf_contents)
$/release.conf:
	echo "$${contents}" > $@


$(addprefix $(ISOROOT)/pools/$(ISO_RELEASE)/,$(ISO_SECTIONS)):
	mkdir -p $@

$(ISOROOT)/dists/%.gz: $(ISOROOT)/dists/%
	gzip -c $< > $@

$(ISOROOT)/dists/$(ISO_RELEASE)/Release: \
	  $/release.conf \
		$(foreach arch,$(ISO_ARCHS),\
		  $(foreach section,$(ISO_SECTIONS),\
			  $(ISOROOT)/dists/$(ISO_RELEASE)/$(section)/binary-$(arch)/Packages \
			  $(ISOROOT)/dists/$(ISO_RELEASE)/$(section)/binary-$(arch)/Packages.gz \
				$(ISOROOT)/dists/$(ISO_RELEASE)/$(section)/debian-installer/binary-$(arch)/Packages \
				$(ISOROOT)/dists/$(ISO_RELEASE)/$(section)/debian-installer/binary-$(arch)/Packages.gz \
			  $(ISOROOT)/dists/$(ISO_RELEASE)/$(section)/binary-$(arch)/Release))
	apt-ftparchive -c $< release $(ISOROOT)/dists/$(ISO_RELEASE) > $@

$(ISOROOT)/dists/$(ISO_RELEASE)/Release.gpg: $(ISOROOT)/dists/$(ISO_RELEASE)/Release
	GNUPGHOME=$(gnupg.home) gpg --yes --no-tty --default-key $(gnupg.default-key-id) --passphrase-file $(gnupg.keyphrase-file) --output $@ -ba $<

define late_contents
#!/bin/sh
# THIS SCRIPT IS FOR USING BY DEBIAN-INSTALLER ONLY

set -e

# repo
mkdir -p /target/var/lib/mirror/ubuntu
cp -r /cdrom/pools /target/var/lib/mirror/ubuntu
cp -r /cdrom/dists /target/var/lib/mirror/ubuntu
cp -r /cdrom/indices /target/var/lib/mirror/ubuntu
mkdir -p /target/etc/apt/sources.list.d
rm -f /target/etc/apt/sources.list
echo "deb file:/var/lib/mirror/ubuntu precise main restricted universe multiverse" > /target/etc/apt/sources.list.d/local.list

# rpm
mkdir -p /target/var/lib/mirror
cp -r /cdrom/centos /target/var/lib/mirror

# gnupg
cp -r /cdrom/gnupg /target/root/.gnupg
chown -R root:root /target/root/.gnupg
chmod 700 /target/root/.gnupg
chmod 600 /target/root/.gnupg/*

# bootstrap
mkdir -p /target/var/lib/mirror/bootstrap
cp /cdrom/bootstrap/linux /target/var/lib/mirror/bootstrap/linux
cp /cdrom/bootstrap/initrd.gz /target/var/lib/mirror/bootstrap/initrd.gz

mkdir -p /target/root
cp /cdrom/bootstrap/bootstrap.rsa /target/root/bootstrap.rsa
chmod 640 /target/root/bootstrap.rsa

# netinst
mkdir -p /target/var/lib/mirror/netinst
cp /cdrom/netinst/* /target/var/lib/mirror/netinst

# nailgun
mkdir -p /target/opt
cp -r /cdrom/nailgun /target/opt

#system
cp -r /cdrom/sync/* /target/
in-target update-rc.d chef-client disable

# eggs
cp -r /cdrom/eggs /target/var/lib/mirror

# gems
cp -r /cdrom/gems /target/var/lib/mirror

endef

$(ISOROOT)/bin/late: export contents:=$(late_contents)
$(ISOROOT)/bin/late:
	@mkdir -p $(@D)
	echo "$${contents}" > $@
	chmod +x $@



$/apt/state/%: $(BINARIES_DIR)/ubuntu/precise/state/% ; $(ACTION.COPY)

$(ISOROOT)/bootstrap/bootstrap.rsa: bootstrap/ssh/id_rsa ; $(ACTION.COPY)
ifeq ($(BOOTSTRAP_REBUILD),1)
$(ISOROOT)/bootstrap/%: $(BUILD_DIR)/bootstrap/% ; $(ACTION.COPY)
else
$(ISOROOT)/bootstrap/%: $(BINARIES_DIR)/bootstrap/% ; $(ACTION.COPY)
endif
$(ISOROOT)/netinst/%: $(BINARIES_DIR)/netinst/% ; $(ACTION.COPY)

$(ISOROOT)/gnupg:
	mkdir -p $@
$(ISOROOT)/gnupg/%: gnupg/% ; $(ACTION.COPY)
$(ISOROOT)/sync:
	mkdir -p $@
$(ISOROOT)/sync/%: iso/sync/% ; $(ACTION.COPY)
$(ISOROOT)/indices/override.$(ISO_RELEASE).extra.main: $/override.$(ISO_RELEASE).extra.main ; $(ACTION.COPY)
$(ISOROOT)/indices/%: $(BINARIES_DIR)/ubuntu/$(ISO_RELEASE)/indices/% ; $(ACTION.COPY)
$(ISOROOT)/nailgun/cookbooks/%: cookbooks/% ; $(ACTION.COPY)
$(ISOROOT)/nailgun/os-cookbooks/%: cooks/% ; $(ACTION.COPY)
$(ISOROOT)/nailgun/solo/%: iso/solo/% ; $(ACTION.COPY)
$(ISOROOT)/nailgun/bin/%: bin/% ; $(ACTION.COPY)
$(ISOROOT)/nailgun/%: nailgun/% ; $(ACTION.COPY)
$(ISOROOT)/eggs:
	mkdir -p $@
$(ISOROOT)/eggs/%: $(BINARIES_DIR)/eggs/% ; $(ACTION.COPY)


$(ISOROOT)/gems/gems:
	mkdir -p $@

$(ISOROOT)/gems/gems/%: $(BINARIES_DIR)/gems/% | $(ISOROOT)/gems/gems
	echo $@
	$(ACTION.COPY)

$/isoroot-gems.done: $(addprefix $(ISOROOT)/gems/gems/,$(call find-files,$(BINARIES_DIR)/gems))
	gem generate_index -d $(ISOROOT)/gems
	$(ACTION.TOUCH)

# MAIN ISO RULE

$/nailgun-ubuntu-12.04-amd64.iso: $/isoroot.done $(ISOROOT)/md5sum.txt
	rm -f $@
	mkisofs -r -V "Mirantis Nailgun" \
		-cache-inodes \
		-J -l -b isolinux/isolinux.bin \
		-c isolinux/boot.cat -no-emul-boot \
		-boot-load-size 4 -boot-info-table \
		-o $@ $(ISOROOT)

endif

