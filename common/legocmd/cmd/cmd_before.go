package cmd

import (
	"github.com/urfave/cli"
	"github.com/vmzn/wand-server/common/legocmd/log"
)

func Before(ctx *cli.Context) error {
	if ctx.GlobalString("path") == "" {
		log.Panic("Could not determine current working directory. Please pass --path.")
	}

	err := createNonExistingFolder(ctx.GlobalString("path"))
	if err != nil {
		log.Panicf("Could not check/create path: %v", err)
	}

	if ctx.GlobalString("server") == "" {
		log.Panic("Could not determine current working server. Please pass --server.")
	}

	return nil
}