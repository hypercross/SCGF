log = (s)-> console.log s
randInt = (n)-> Math.floor Math.random() * n

log 'setup'
log 'start'
for i in [8..0]
    console.log randInt i
