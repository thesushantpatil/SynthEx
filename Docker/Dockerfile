FROM rocker/r-ver:3.5.2
# FROM rocker/r-base:latest

LABEL maintainer="Alan Hoyle <alanh@unc.edu>"
LABEL description="The SynthEx Copy Number Variant caller"

RUN apt-get update
RUN apt-get install -y libcurl4-openssl-dev  libssl-dev python zlib1g-dev

ENV bedtools_version 2.27.1

ADD https://github.com/arq5x/bedtools2/releases/download/v${bedtools_version}/bedtools-${bedtools_version}.tar.gz /tmp/

RUN cd /tmp/ \
    && tar xzvf bedtools-${bedtools_version}.tar.gz \
    && cd bedtools2 \
    && make \
    && make install \
    && rm /tmp/bedtools-${bedtools_version}.tar.gz \
    && rm -rf /tmp/bedtools2/test \
    && rm -rf /tmp/bedtools2/src \
    && rm -rf /tmp/bedtools2/docs

RUN R -q -e "install.packages(c('devtools', 'covr', 'roxygen2', 'testthat','optparse'), repos = 'https://cloud.r-project.org/')" &&\
rm -rf /tmp/*

RUN Rscript -e ' install.packages("BiocManager", repos = "https://cloud.r-project.org/") ; BiocManager::install() ; BiocManager::install("DNAcopy")'
RUN Rscript -e 'devtools::install_github("thesushantpatil/SynthEx")'

COPY Rprofile.site /etc/R/
COPY SynthEx.R /SynthEx.R

ENTRYPOINT ["Rscript", "/SynthEx.R"]
CMD ["--help"]

# CMD ["R"]
