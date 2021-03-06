ARG BASE_YUM_REPO=testing

FROM opensciencegrid/software-base:3.5-el7-${BASE_YUM_REPO}

# Previous arg has gone out of scope
ARG BASE_YUM_REPO=testing

# token auth require HTCondor 8.9.x
RUN useradd osg \
 && if [[ $BASE_YUM_REPO = release ]]; then \
       yumrepo=osg-upcoming; else \
       yumrepo=osg-upcoming-$BASE_YUM_REPO; fi \
 && mkdir -p ~osg/.condor \
 && yum -y --enablerepo=$yumrepo install \
        condor \
        osg-wn-client \
        redhat-lsb-core \
        singularity \
 && yum clean all \
 && mkdir -p /etc/condor/passwords.d /etc/condor/tokens.d \
 && curl -s -o /usr/sbin/osgvo-user-job-wrapper https://raw.githubusercontent.com/opensciencegrid/osg-flock/master/job-wrappers/user-job-wrapper.sh \
 && curl -s -o /usr/sbin/osgvo-node-advertise https://raw.githubusercontent.com/opensciencegrid/osg-flock/master/node-check/osgvo-node-advertise \
 && chmod 755 /usr/sbin/osgvo-user-job-wrapper /usr/sbin/osgvo-node-advertise

COPY condor_master_wrapper /usr/sbin/
RUN chmod 755 /usr/sbin/condor_master_wrapper

# Override the software-base supervisord.conf to throw away supervisord logs
COPY supervisord.conf /etc/supervisord.conf

RUN yum -y install git \
 && git clone https://github.com/cvmfs/cvmfsexec /cvmfsexec \
 && cd /cvmfsexec \
 && ./makedist osg \
 # /cvmfs-cache and /cvmfs-logs is where the cache and logs will go; possibly bind-mounted. \
 # Needs to be 1777 so the unpriv user can use it. \
 # (Can't just chown, don't know the UID of the unpriv user.) \
 && mkdir -p /cvmfs-cache /cvmfs-logs \
 && chmod 1777 /cvmfs-cache /cvmfs-logs \
 && rm -rf dist/var/lib/cvmfs log \
 && ln -s /cvmfs-cache dist/var/lib/cvmfs \
 && ln -s /cvmfs-logs log \
 # tar up and delete the contents of /cvmfsexec so the unpriv user can extract it and own the files. \
 && tar -czf /cvmfsexec.tar.gz ./* \
 && rm -rf ./* \
 # Again, needs to be 1777 so the unpriv user can extract into it. \
 && chmod 1777 /cvmfsexec

# Space separated list of repos to mount at startup (if using cvmfsexec);
# leave this blank to disable cvmfsexec
ENV CVMFSEXEC_REPOS=
# The proxy to use for CVMFS; leave this blank to use the default
ENV CVMFS_HTTP_PROXY=
# The quota limit in MB for CVMFS; leave this blank to use the default
ENV CVMFS_QUOTA_LIMIT=

COPY entrypoint.sh /bin/entrypoint.sh
COPY 10-setup-htcondor.sh /etc/osg/image-init.d/
COPY 10-cleanup-htcondor.sh /etc/osg/image-cleanup.d/
COPY 10-htcondor.conf /etc/supervisord.d/
COPY 50-main.config /etc/condor/config.d/
RUN chmod 755 /bin/entrypoint.sh
 
RUN chown -R osg: ~osg 

RUN mkdir -p /pilot && chmod 1777 /pilot

WORKDIR /pilot
# We need an ENTRYPOINT so we can use cvmfsexec with any command (such as bash for debugging purposes)
ENTRYPOINT ["/bin/entrypoint.sh"]
# Adding ENTRYPOINT clears CMD
CMD ["/usr/local/sbin/supervisord_startup.sh"]
