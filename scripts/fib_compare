#!/bin/bash

echo "=== Fibonacci(24) Performance Comparison ==="
echo "Total function calls: 75,025"
echo ""

# Ruby
cat > /tmp/fib.rb << 'EOF'
def fib(n)
  n < 2 ? n : fib(n - 1) + fib(n - 2)
end

start = Time.now
result = fib(24)
duration = Time.now - start

puts "Ruby:     #{result} in #{'%.6f' % duration}s = #{(75025 / duration).to_i} calls/sec"
EOF

# Python
cat > /tmp/fib.py << 'EOF'
import time

def fib(n):
    return n if n < 2 else fib(n - 1) + fib(n - 2)

start = time.time()
result = fib(24)
duration = time.time() - start

print(f"Python:   {result} in {duration:.6f}s = {int(75025 / duration)} calls/sec")
EOF

# JavaScript (Node.js)
cat > /tmp/fib.js << 'EOF'
function fib(n) {
    return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

const start = Date.now();
const result = fib(24);
const duration = (Date.now() - start) / 1000;

console.log(`Node.js:  ${result} in ${duration.toFixed(6)}s = ${Math.floor(75025 / duration)} calls/sec`);
EOF

# Run benchmarks
ruby /tmp/fib.rb
python3 /tmp/fib.py
node /tmp/fib.js 2>/dev/null || echo "Node.js:  (not installed)"

# Gene
if [ -f ./bin/fibonacci ]; then
    echo -n "Gene VM:  "
    ./bin/fibonacci | grep -E "(Result:|Time:|Performance:)" | sed 's/Result: fib(24) = //' | sed 's/Time: /in /' | sed 's/ seconds/s/' | sed 's/Performance: / = /' | sed 's/\. function/ /' | tr '\n' ' ' | awk '{print $1 " " $2 " " $3 " " $4 " " $5 " calls/sec"}'
fi

# Clean up
rm -f /tmp/fib.rb /tmp/fib.py /tmp/fib.js