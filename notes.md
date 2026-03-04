

# Structure of server



configure port and set of routers

main loop
  wait
  check for request
  if request found
    identify request type
    switch on type
      route to appropriate route based on type
      spawn thread to handle route
