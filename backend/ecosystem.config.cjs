module.exports = {
  apps: [{
    name: 'umao-vd',
    script: 'server.js',
    env: { PORT: 3333, BASE_PATH: "/vd" }
  }]
};