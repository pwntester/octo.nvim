build:
	rm -rf lua/*
	tl build
	rsync -zarv --include="*/" --include="*.lua" --exclude="*" "src/" "lua/"
