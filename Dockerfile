FROM registry.theopencloset.net/opencloset/perl:latest
MAINTAINER Hyungsuk Hong <aanoaa@gmail.com>

RUN groupadd opencloset && useradd -g opencloset opencloset

WORKDIR /tmp
COPY cpanfile cpanfile
RUN cpanm --notest \
    --mirror http://www.cpan.org \
    --mirror http://cpan.theopencloset.net \
    --installdeps .

# Everything up to cached.
WORKDIR /home/opencloset/service/cpan.theopencloset.net
COPY . .
RUN chown -R opencloset:opencloset .

USER opencloset
ENV MOJO_HOME=/home/opencloset/service/cpan.theopencloset.net
ENV MOJO_CONFIG=app.conf

ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["hypnotoad"]

EXPOSE 5000
