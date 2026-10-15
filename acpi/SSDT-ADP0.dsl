/*
 * AC adapter on macOS (ASUS 7940HX laptop). The firmware's ADP0._PSR reads the EC (SACM -> \ACPF) and then, whenever the
 * state differs from the last one it saw, tells AMD's ALIB (function 1, power-source change). On macOS that ALIB call
 * fails (AE_AML_NO_RETURN_VALUE: one of its paths returns nothing), which aborts _PSR every time - so macOS never learns
 * that a charger is plugged in (ExternalConnected = No, FileVault encryption stays paused).
 * OpenCore renames the original method to XPSR (DSDT only); this _PSR reads the EC the same way, without ALIB, on macOS,
 * and calls the original everywhere else.
 */
DefinitionBlock ("", "SSDT", 2, "HACK", "ADP0FIX", 0x00000000)
{
    External (_SB_.PCI0.SBRG.ADP0, DeviceObj)
    External (_SB_.PCI0.SBRG.ADP0.XPSR, MethodObj)
    External (_SB_.PCI0.SBRG.ECOK, IntObj)
    External (_SB_.PCI0.SBRG.SACM, MethodObj)

    Scope (_SB.PCI0.SBRG.ADP0)
    {
        Method (_PSR, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                If (\_SB.PCI0.SBRG.ECOK)
                {
                    Return (\_SB.PCI0.SBRG.SACM ())
                }
                Return (One)
            }
            Return (XPSR ())
        }
    }
}
