-- Samsung Galaxy Tab S5e (gts4lvwifi) panel calibration.
-- The FTS controller is mounted a quarter-turn from the native DSI panel.
hl.config({
  input = {
    touchdevice = {
      output = "DSI-1",
      transform = 3,
    },
  },
})
