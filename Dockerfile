FROM debian:bookworm-slim

# Install Make, wget, tar tools, and procps (for pkill)
RUN apt-get update && apt-get install -y make wget xz-utils procps && rm -rf /var/lib/apt/lists/*

# download Zig 0.15.2
RUN wget https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz && \
    tar -xf zig-x86_64-linux-0.15.2.tar.xz && \
    mv zig-x86_64-linux-0.15.2 /usr/local/zig && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig && \
    rm zig-x86_64-linux-0.15.2.tar.xz

WORKDIR /app

COPY . .

CMD ["make", "run"]
