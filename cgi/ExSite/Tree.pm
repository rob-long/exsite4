#-----------------------------------------------------------------------
#
#   Copyright 2001-2006 Exware Solutions, Inc.  http://www.exware.com
#
#   This file is part of ExSite WebWare (ExSite, for short).
#
#   ExSite is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   ExSite is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with ExSite; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Users requiring warranty coverage and/or support may arrange alternate
#   commercial licensing for ExSite, by contacting Exware Solutions 
#   via the website noted above.
#
#----------------------------------------------------------------------------

# POD documentation at end of file

### TODO:
### - allow Tree to hold objects as well as datahashes
### - object is in $tree->{node}{$key}{obj}
### - data is in $tree->{node}{$key}{data}

package ExSite::Tree;

use strict;
use ExSite::Config;
use ExSite::Base;
use ExSite::Misc;
use vars qw(@ISA $depth);
@ISA = qw(ExSite::Base);

# Tree constructor

sub new ($$$@) {
    my ($this,$id_key,$parent_key,@data) = @_;
    my $obj = {};
    my $class = ref($this) || $this;
    bless $obj, $class;
    $obj->initialize_object;
    $obj->{top} = [];   # top-level node order
    $obj->{nodes} = {}; # node storage
    $obj->{id_key} = $id_key;          # default keys
    $obj->{parent_key} = $parent_key;
    if (@data > 0) { $obj->addnodes(\@data); }
    return $obj;
}

# add a bunch of nodes

sub addnodes {
    my ($this,$data,$id_key,$parent_key,$ignore_parent) = @_;
    foreach my $d (@$data) {
	$this->addnode($d,$id_key,$parent_key,$ignore_parent);
    }
}

# add a single node

sub addnode {
    my ($this,$d,$id_key,$parent_key,$ignore_parent) = @_;
    my $node = $this->insert_node($d,$id_key,$parent_key);
    # add node to the child list of its parent
    my $parent_id = $node->{data}{$node->{parent_key}};
    if ($parent_id && grep(/^$parent_id$/,@{$ignore_parent})==0) {
	my $parent = $this->getnode($parent_id,1);
	push @{$parent->{child}}, $node;
	### FIXME: don't add node to children, if already there
    }
    else {
	# no parent - must be a top-level node
	push @{$this->{top}}, $node;
    }
}

# add a single node as a top-level node (slightly more efficient than
# calling addnode() with $ignore_parent)

sub addtopnode {
    my ($this,$d,$id_key,$parent_key) = @_;
    my $node = $this->insert_node($d,$id_key,$parent_key);
    # add node to the topnode list
    push @{$this->{top}}, $node;
}

# put the basic node data into the tree

sub insert_node {
    my ($this,$d,$id_key,$parent_key) = @_;
    my $id = $id_key || $this->{id_key};
    my $pid = $parent_key || $this->{parent_key};
    my $key = $d->{$id};
    # add node to the tree
    if (exists $this->{node}{$key}) {
	# overwrite existing node
	$this->{node}{$key}{id_key} = $id;
	$this->{node}{$key}{parent_key} = $pid;
	$this->{node}{$key}{data} = $d;
	$this->{node}{$key}{parent} = $d->{$pid};
    }
    else {
	# insert new node
	$this->{node}{$key} = {
	    id_key => $id,
	    parent_key => $pid,
	    data => $d,
	    parent => $d->{$pid},
	    child => [],
	};
    }
    return $this->{node}{$key};
}

# remove a single node - plus all of its descendants

sub delnode {
    my ($this,$id,$fast) = @_;
    # $fast does a fast delete of all children of a parent
    # use this when pruning whole child branches of the tree
    my $node = ref $id ? $id : $this->getnode($id,0);
    return 0 if (! $node);

    # delete the children first
    my @child = $this->get_child_nodes($id);
    foreach my $c (@child) {
	$this->delnode($c->{data}{$c->{id_key}},1);
    }

    # delete ourself from the parent list
    my $parent = $this->getnode($node->{parent});
    if ($parent) {
	if ($fast) {
	    if (@{$parent->{child}} > 0) {
		# delete everything for speed
		$parent->{child} = [];
	    }
	}
	else {
	    # delete just ourself
	    my $pos = 0;
	    foreach my $c (@{$parent->{child}}) {
		last if ($c->{data}{$c->{id_key}} == $id);
		$pos++;
	    }
	    splice(@{$parent->{child}},$pos,1);
	}
    }

    # delete ourself from the topnodes
    my $pos = 0;
    foreach my $n (@{$this->{top}}) {
	if ($n->{data}{$n->{id_key}} == $id) {
	    splice(@{$this->{top}},$pos,1);
	    last;
	}
	$pos++;
    }

    # now delete ourself
    delete $this->{node}{$id};
    return 1;
}

# splice - remove a node, but try to reattach its descendants into its place

sub splice {
    my ($this,$id) = @_;
    my $node = ref $id ? $id : $this->getnode($id,0);
    return 0 if (! $node);

    my $parent_key = $node->{parent_key};
    my $parent_id = $node->{data}{$parent_key};

    # remap the children first
    my @child = $this->get_child_nodes($id);
    foreach my $c (@child) {
	$c->{parent_key} = $parent_key;
	$c->{data}{$parent_key} = $parent_id;
	$c->{parent} = $parent_id;
    }

    # topnode?
    my $topnode = 0;
    foreach my $n (@{$this->{top}}) {
	if ($n->{data}{$n->{id_key}} == $node->{data}{$node->{id_key}}) {
	    $topnode = 1; last;
	}
    }
    if ($topnode) {
        # promote our former children into topnodes
	foreach my $c (@child) {
	    push @{$this->{top}},$c;
	}
	# remove self from topnodes
	my $pos = 0;
	foreach my $n (@{$this->{top}}) {
	    if ($n->{data}{$n->{id_key}} == $id) {
		splice(@{$this->{top}},$pos,1);
		last;
	    }
	    $pos++;
	}
    }

    # now delete ourself
    delete $this->{node}{$id};

    return 1;
}

# replace node data, but maintain existing node relationships

sub replacenode {
    my ($this,$id,$d,$id_key,$parent_key,$ignore_parent) = @_;
    if (exists $this->{node}{$id}) {
	my $node = $this->{node}{$id};
	# get original parent
	my $parent_key = $node->{parent_key};
	my $parent_id = $node->{data}{$parent_key};
	# overwrite existing node data
	$node->{data} = $d;
	# BUT keep the parent ID same as before to maintain tree integrity
	$node->{data}{$parent_key} = $parent_id;
	# add a pointer from new node key
	$this->{node}{$d->{$id_key || $this->{id_key}}} = $this->{node}{$id};
    }
    else {
	$this->addnode($d,$id_key,$parent_key,$ignore_parent);
    }
}

# fetch a node, optionally creating it if it does not exist

sub getnode ($$$) {
    my ($this,$id,$create_flag) = @_;
    if (! exists $this->{node}{$id} && $create_flag) {
	$this->{node}{$id} = {
	    id_key => $this->{id_key},
	    parent_key => $this->{parent_key},
	    data => { $this->{id_key} => $id },
	    child => [],
	};
    }
    return exists $this->{node}{$id} ?
	$this->{node}{$id} :
	undef;
}

sub getnode_data ($$$) {
    my ($this,$id,$create_flag) = @_;
    my $node = $this->getnode($id,$create_flag);
    return $node ? $node->{data} : undef;
}

# fetch the parent of a node

sub get_parent_node ($$) {
    my ($this,$id) = @_;
    my $node = $this->getnode($id);
    if ($node && $node->{data}{$node->{parent_key}}) {
	return $this->getnode($node->{parent});
    }
    return undef;
}

sub get_parent_data ($$) {
    my ($this,$id) = @_;
    my $p = $this->get_parent_node($id);
    return $p ? $p->{data} : undef;
}

sub get_parent {
    return &get_parent_data(@_);
}

# fetch the children of a node

sub get_child_nodes ($$) {
    my ($this,$id) = @_;
    my @children;
    if (exists $this->{node}{$id}) {
	@children = @{$this->{node}{$id}{child}}
    }
    return wantarray ? @children : \@children;
}

sub get_child_data ($$) {
    my ($this,$id) = @_;
    my @children = $this->get_child_nodes($id);
    foreach my $c (@children) {
	$c = $c->{data};
    }
    return wantarray ? @children : \@children;
}

sub get_child {
    return &get_child_data(@_);
}

sub get_child_by_name {
    my ($this,$id,$name) = @_;
    my $namekey = $this->{name_key} || $this->{id_key};
    my @child = $this->get_child_data($id);
    my %child = &keywise($namekey,\@child);
    return $child{$name};
}

# return the top-level nodes

sub get_topnodes {
    my ($this) = @_;
    return wantarray ? @{$this->{top}} : $this->{top};
}

sub get_topnodes_data {
    my ($this) = @_;
    my @topnode = $this->get_topnodes();
    foreach my $n (@topnode) {
	$n = $n->{data};
    }
    return wantarray ? @topnode : \@topnode;
}

# return the top-level node relative to a starting node

sub get_ancestor_node {
    my ($this,$id) = @_;
    my $node; 
    while ($id) {
	if (exists $this->{node}{$id}) {
	    $node = $this->{node}{$id};
	    $id = $node->{data}{$node->{parent_key}};
	}
	else {
	    # no such node, which means we are at the top
	    return $node;
	}
    }
    return $node;
}

sub get_ancestor_data {
    my ($this,$id) = @_;
    my $node = $this->get_ancestor_node($id);
    if (ref $node eq "HASH") {
	return $node->{data};
    }
    return undef;
}

# return the next node in the tree (depth-first traversal)
# id refers to the "current" node, next node is relative to this
### FIXME: use collapse() make a flat list, then search this list

sub get_next_node {
    my ($this,$id) = @_;
    if (exists $this->{node}{$id}) {
	# first child is next node
	my @node = $this->get_child_nodes($id);
	if (@node > 0) {
	    return $node[0];
	}
	# no children; next sibling is next node
	my $parent = $this->get_parent_node($id);
	my $pid = $this->id($parent);
	@node = $this->get_child_nodes($pid);  # our siblings
	for (my $inode=0; $inode < scalar @node; $inode++) {
	    if ($this->id($node[$inode]) == $id) {
		if ($inode < $#node) {
		    return $node[$inode+1];
		}
	    }
	}
	# no more siblings; parent's next sibling is next node
	while ($parent = $this->get_parent_node($pid)) {
	    @node = $this->get_child_nodes($this->id($parent)); # our uncles
	    for (my $inode=0; $inode < scalar @node; $inode++) {
		if ($this->id($node[$inode]) == $pid) {
		    if ($inode < $#node) {
			return $node[$inode+1];
		    }
		}
	    }
	    $pid = $this->id($parent);
	}
	# no more parents; next topnode is next node
	my $ancestor_id = $this->id($this->get_ancestor_node($id));
	@node = $this->get_topnodes();
	for (my $inode=0; $inode < scalar @node; $inode++) {
	    if ($this->id($node[$inode]) == $ancestor_id) {
		if ($inode < $#node) {
		    return $node[$inode+1];
		}
	    }
	}
    }
    return undef;
}

sub get_next_data {
    my ($this,$id) = @_;
    my $nextnode = $this->get_next_node($id);
    return $nextnode ? $nextnode->{data} : undef;
}

# get the ID of a node

sub id {
    my ($this,$node) = @_;
    if (ref $node eq "HASH" && ref $node->{data} eq "HASH") {
	return $node->{data}{$node->{id_key}};
    }
    return undef;
}

# exists - check if the tree includes a particlar node

sub exists {
    my ($this,$id) = @_;
    return exists $this->{node}{$id};
}

# find nodes that match a pattern

sub find {
    my ($this,$pattern,$id) = @_;
    my ($out,@node);
    my $clist;
    $this->{found} = [];
    if ($id && exists ($this->{node}{$id})) {
	if (! $pattern || &match_hash($pattern,$this->{node}{$id}{data})) {
	    push @$clist,$this->getnode_data($id);
	}
	@node = @{$this->{node}{$id}{child}};
    }
    else {
	@node = $this->get_topnodes();
    }
    $this->find_r($pattern,@node);
    my @data = map { $_->{data} } @{$this->{found}};
    return wantarray ? @data : \@data;
}

sub find_r {
    my ($this,$pattern,@node) = @_;
    foreach my $n (@node) {
	push @{$this->{found}},$n if (! $pattern || &match_hash($pattern,$n->{data}));
	$this->find_r($pattern,$this->get_child_nodes($n->{data}{$n->{id_key}}));
    }
}

# count nodes that match a pattern
# NB: the starting node is included in the count

sub count {
    my ($this,$pattern,$id) = @_;
    my ($out,@node);
    my $count = 0;
    if (exists ($this->{node}{$id})) {
	#$count++;
	$count++ if (! $pattern || &match_hash($pattern,$this->{node}{$id}{data}));
	@node = @{$this->{node}{$id}{child}};
    }
    else {
	@node = $this->get_topnodes();
    }
    $count += $this->count_r($pattern,@node);
    return $count;
}

sub count_r {
    my ($this,$pattern,@node) = @_;
    my $count = 0;
    foreach my $n (@node) {
	$count++ if (! $pattern || &match_hash($pattern,$n->{data}));
	$count += $this->count_r($pattern,$this->get_child_nodes($n->{data}{$n->{id_key}}));
    }
    return $count;
}

# collapse the tree into a simple array (ordered depth-first)
# NB: the starting node is NOT included in the array

sub collapse {
    my ($this,$id) = @_;
    my @node;
    my $clist = [];  # the collapsed array of nodes
    if (exists ($this->{node}{$id})) {
	@node = @{$this->{node}{$id}{child}};
    }
    else {
	@node = $this->get_topnodes();
    }
    foreach my $n (@node) {
	push @$clist, $n->{data};
	$this->collapse_r($n,\$clist);
    }
    return wantarray ? @$clist : $clist;
}

sub collapse_r {
    my ($this,$node,$clist) = @_;
    # collapse all nodes below $node, appending them to @$$clist
    # NB: $clist is a reference to an array reference
    my ($out,@node);
    foreach my $n ($this->get_child_nodes($node->{data}{$node->{id_key}})) {
	push @{${$clist}}, $n->{data};
	$this->collapse_r($n,$clist);
    }
}

# get_leaves: collapse the tree into a simple array of leaf nodes

sub get_leaves {
    my ($this,$id) = @_;
    my ($out,@node);
    my $clist = [];  # the collapsed array of nodes
    if (exists ($this->{node}{$id})) {
	@node = ($this->{node}{$id});
	push @node, @{$this->{node}{$id}{child}};
    }
    else {
	@node = $this->get_topnodes();
    }
    foreach my $n (@node) {
	if (@{$n->{child}} == 0) {
	    push @$clist, $n->{data};
	}
	$this->get_leaves_r($n,\$clist);
    }
    return wantarray ? @$clist : $clist;
}

sub get_leaves_r {
    my ($this,$node,$clist) = @_;
    # collapse all nodes below $node, appending them to @$$clist
    # NB: $clist is a reference to an array reference
    my ($out,@node);
    foreach my $n ($this->get_child_nodes($node->{data}{$node->{id_key}})) {
	if (@{$n->{child}} == 0) {
	    push @{${$clist}}, $n->{data};
	}
	$this->get_leaves_r($n,$clist);
    }
}

sub subtree {
    my ($this,$id,$match) = @_;
    return undef if (!$id || !exists $this->{node}{$id});
    my ($n,@newnode,@oldnode);
    # start with new root node
    push @oldnode, $this->{node}{$id};
    # ignore parent of root node
    my $ignore = $oldnode[0]{data}{$oldnode[0]{parent_key}};
    # add all descendant nodes to our list
    while (@oldnode > 0) {
	$n = shift @oldnode;
	if (@{$n->{child}} > 0) { push @oldnode, @{$n->{child}}; }
	push @newnode, $n;
	if (scalar @oldnode + scalar @newnode > $config{max_tree_size}) {
	    $this->error("exceeded maximum tree size");
	    last;
	}
    }
    # build a new tree from our list of nodes
    my $tree = new ExSite::Tree($this->{id_key},$this->{parent_key});
    foreach $n (@newnode) {
	next if ($match && ! &match_hash($match,$n->{data}));
	$tree->addnode($n->{data},$n->{id_key},$n->{parent_key},[$ignore]);
    }
    return $tree;
}

# path_to - return the path to a node ID

sub path_to {
    my ($this,$id,$name) = @_;
    $name or $name = $this->{name_key} || $this->{id_key};
    my %done;
    my @path;
    while ($id) {
	if ($done{$id}) {
	    # circular reference - error
	    $this->error("ExSite::Tree: circular reference at node $id");
	    $id = undef;
	}
	else {
	    $done{$id} = 1;
	    my $node = $this->getnode($id);
	    if ($node) {
		unshift @path, $node->{data}{$name};
		$id = $node->{data}{$this->{parent_key}};
	    }
	    else {
		$id = undef;
	    }
	}
    }
    return wantarray ? @path : "/".join("/",@path);
}

# path_is - return the node that a path represents

sub path_is {
    my ($this,$path,$name,$startnode) = @_;
    $name or $name = $this->{name_key} || $this->{id_key};
    my @npath;
    my @path = (ref $path) eq "ARRAY" ? @$path : split /\//, $path;
    shift @path if (! $path[0]); # paths usually start with /
    my $node; # = $startnode ? $this->getnode($startnode) : undef;
    my @nodes = $startnode ? $this->get_child_nodes($startnode) : $this->get_topnodes();
    #if ($node) { push @npath, $node->{data}; }
    my $pname = shift @path;
    do {
	my $found = 0;
	while (! $found && (my $n = shift @nodes)) {
	    if ($n->{data}{$name} eq $pname) {
		$node = $n;
		push @npath, $node->{data};
		@nodes = $this->get_child_nodes($n->{data}{$n->{id_key}});
		$found = 1;
	    }
	}
	if (! $found) {
	    # unknown path element
	    $this->warn("ExSite::Tree: unknown path element: $pname");
	    push @npath, undef;
	    return wantarray ? @npath : undef;
	}
	$pname = shift @path;
    } while ($pname);
    if ($node) { 
	#return wantarray ? %{$node->{data}} : $node->{data}{$node->{id_key}};
	return wantarray ? @npath : $node->{data};
    }
    return undef;
}

# ancestor/descendant tests

sub has_ancestor {
    my ($this,$id,$ancestor_id) = @_;
    my $node = $this->getnode($id);
    my %done;
    while ($node) {
	my $node_id = $node->{data}{$node->{id_key}};
	return 0 if ($done{$node_id}); # tree loop
	return 1 if ($node_id == $ancestor_id);
	$node = $this->get_parent_node($node_id);
	$done{$node_id} = 1;
    }
    return 0;
}

sub has_descendant {
    my ($this,$id,$descendant_id) = @_;
    return $this->has_ancestor($descendant_id,$id);
}

# display a summary of the tree contents
# NB: the starting node is NOT included in the dump

sub dump {
    my ($this,$id,@keys) = @_;
    if (scalar @keys == 0) {
	@keys = ($this->{name_key} || $this->{id_key});
    }
    my ($out,@node);
    if (exists ($this->{node}{$id})) {
	@node = @{$this->{node}{$id}{child}};
    }
    else {
	@node = $this->get_topnodes();
    }
    $depth = 0;
    foreach my $n (@node) {
	if (@keys == 0) { @keys = ($n->{id_key}); }
	foreach my $k (@keys) {
	    $out .= $n->{data}{$k}." ";
	}
	$out .= "\n";
	$depth++;
	$out .= $this->dump_r($n,@keys);
	$depth--;
    }
    return $out;
}

sub dump_r {
    my ($this,$node,@keys) = @_;
    my ($out,@node);
    foreach my $n ($this->get_child_nodes($node->{data}{$node->{id_key}})) {
	if (@keys == 0) { @keys = ($n->{id_key}); }
	foreach (1..$depth) { $out .= "  "; }
	foreach my $k (@keys) {
	    $out .= $n->{data}{$k}." ";
	}
	$out .= "\n";
	$depth++;
	$out .= $this->dump_r($n,@keys);
	$depth--;
    }
    return $out;
}

1;

=pod

=head1 ExSite::Tree

ExSite::Tree is a generic tool for managing heirarchical tree
structures such as are found in ExSite.  It assumes that each tree
node is essentially an ExSite datahash, and each node has a
single parent node.

Each tree node is a hash containing the following keys:

    data - reference to a hash containing the node data
    id_key - the key in %$data that looks up the node ID
    parent_key - the key in %$data that looks up the node parent ID
    parent - the value in %$data that is the node parent ID
    child - an array of child nodes under this node

The first value, C<data>, is a datahash containing arbitrary node data
formatted as key/value pairs.  The remainder are used for indexing and
navigating the tree nodes.

Typically C<data> is an ExSite datahash, which contains foreign key values 
pointing to other ExSite datahashes.  The primary key of the datahash is
used as C<id_key>, and the foreign key is used as C<parent_key>.  The 
foreign key value is C<parent>, which presumably is the id of another node
in the tree.

Nodes retain the order in which they were inserted into the tree.  That
means that if several nodes are inserted as children of a particular node X, 
then when the children of X are fetched, they will be returned in the same
order they were added to the tree.

=head2 Tree Contruction

Each tree node is a datahash.  One of the hash keys is used as a node
ID, and another is used as a parent ID (collectively, these are the 
index keys).  The index keys can be specifed uniquely for each node,
or for a group of nodes.  You can also set default index keys to be used
for all nodes if nothing specific is given.

When building a tree, consider whether the tree is properly rooted,
meaning that it starts from nodes that have no parents.  If so, then
the tree will automatically detect these root nodes and make them
accessible using the C<get_topnodes> methods.

Sometimes, however, it is necessary to create trees from a partial
data set which is actually just a branch of a larger tree.  In this
case, the topmost node(s) will still have a parent, but the parent
will not be included in the tree data.  In this case, the tree will
not have a natural root, and may not be able to automatically identify
where to begin.  This may not be a problem if you do not need to query
the tree for the topnodes (eg. if you only query by specific node
IDs).  If you do need to query for topnodes, then you should advise the
tree where your partial tree is rooted, either by adding the topnodes
manually (C<addtopnode()>) or by specifying which parent IDs can be
ignored (treated as zero) because they are not included in your data
set.

ExSite Trees are designed to be self-constructing with typical ExSite
data structures.  See the example at the end for more info.

=over 4

=item Create a new tree object

    my $tree = new ExSite::Tree("id_key", "parent_key", @data);

"id_key" and "parent_key" are the index keys for the datahashes in C<@data>.
They are also the default index keys for all other nodes added to the tree.
C<@data> is optional.

=item Add nodes to a tree

    $tree->addnode($data);

    $tree->addnode($data,$id_key,$parent_key,$ignore_parent);

Adds one node whose data is in C<%$data>.  If the index keys are different
from the default for the tree, they can be specified as extra parameters.

The optional C<$ignore_parent> parameter can be used to specify a tree
root other than the natural root.  The natural root would occur where
the parent ID is zero.  However, there are cases where you want to extract
a subset of the natural tree, starting at some set of branches.  In these
cases you want to ignore the parents of those starting branches, so that
the branches are treated as root nodes.  To do this, you can pass an
arrayref of parent IDs to ignore.

    $tree->addnodes($data);

    $tree->addnodes($data,$id_key,$parent_key,$ignore_parent);

Same as above, except C<$data> is taken to be a reference to 
an array of datahashes.

    $tree->addtopnode($data);

    $tree->addtopnode($data,$id_key,$parent_key);

Same as C<addnode()>, except that the node is explictly understood to
be a top-level node with no parent, despite what that parent ID
suggests.

=item Remove nodes from a tree

    $tree->delnode($id);

This removes a node (along with its descendants) from the tree.

    $tree->splice($id);

This removes a node from the tree, but remaps its children to take its
place.

    $tree->replacenode($id,$data);

    $tree->replacenode($id,$data,$id_key,$parent_key);

This replaces the data in the node indexed under C<$id>, with the contents
of C<%$data>.  The replaced node will be indexed under the original 
key as well as under a new key determined from the replacement data.

=back

=head2 Querying the tree

Tree nodes can be fetched as nodes (including the tree indexing parameters)
or as data (ie. the original datahash).  Fetching as nodes is typical for
internal use;  fetching as data is typical for calls from other
packages.  If you fetch the node, the data can be accessed as 
C<$node-E<gt>{data}{...}>.

=over 4

=item Fetch a node

    $tree->getnode($id,$create_flag);

    $tree->getnode_data($id,$create_flag);

Fetches the node indexed under C<$id>.  If C<$create_flag> is true, 
a dummy version of the node will be created if it is not found.

=item Fetch the parent of a node

    $tree->get_parent_node($id);

    $tree->get_parent_data($id);

Fetches the parent of the node indexed under C<$id>.

=item Fetch the children of a node

    $tree->get_child_nodes($id);

    $tree->get_child_data($id);

    $tree->get_child($id);  # synonym for get_child_data()

Fetches the children nodes under node C<$id>.  Returns an array, or
array ref, depending on the list context.

=item Fetch the top-level of the tree

    $tree->get_topnodes();

    $tree->get_topnodes_data();

Fetches the nodes that have no parents.  Returns an array, or
array ref, depending on the list context.

=item Fetch the top-level ancestor of a node

    $tree->get_ancestor_node($id);

    $tree->get_ancestor_data($id);

Search up through the parent links for a node without a parent.

=item Dump the tree

    print $tree->dump();    # dump IDs

    print $tree->dump($id); # dump IDs, starting from $id

    print $tree->dump($id,"key1","key2"); # dump certain keys, starting from $id

Returns a string that illustrates the tree as a nested list of text strings.
Each tree node is shown as its ID, by default, but if alternate keys are 
given, the values under those keys in the node's data will be listed instead.

=item See if the tree contains a particular node

    $tree->exists($id);

This returns true (1) if the node C<$id> exists in the tree.

=item Count nodes

    $tree->count();             # count all nodes

    $tree->count($pattern);     # count nodes that match $pattern

    $tree->count($pattern,$id); # count nodes matching $pattern starting at $id

C<$pattern> is a match hash that limts counted nodes to those whose data 
contains the same key/value pairs as the match hash.  C<$id> sets a starting
node to count from;  only this and descendant nodes are included in the count.

=back

=head2 Tree Transforms

You can convert the tree to other data structures:

=over 4

=item Collapse the tree to a list

    my @list = $tree->collapse($id);

The tree is compressed to a flat list, ordered depth-first.  If C<$id> is
given, only that branch of the tree is collapsed.

Alternatively, you can collapse the tree to a list of leaf nodes only:

    my @list = $tree->get_leaves($id);

Branch nodes (those with child nodes) are excluded from this list.

=item Extract a sub-tree

    my $subtree = $tree->subtree($id,$match);

The subtree is another tree object, comprising a branch of the current
tree starting at node C<$id>.

If the match hash C<$match> is provided, the nodes of the subtree will
be filtered to include only those whose data match the key/value pairs
in C<$match>.  WARNING: if the tree contains closed loops in its node
relationships, it is possible for an infinite loop to result when
copying to the subtree.  For this reason, we prune the subtree at
C<$config{max_tree_nodes}>.  Legitimate subtrees larger than this size
will get truncated.

=back

=head2 Paths

A path is a list of connected nodes in the tree. In list context, it
is given as an array of node datahashes; in scalar context it is a
string /A/B/C/... where A, B, C, etc. are the node IDs. If you define
a special node key using

    $tree->set("node_key", $my_node_key);

it will use that key name to name the path elements instead.

    my @path = $tree->path_to($id, $name);
    my $path = $tree->path_to($id, $name);

returns the path to node ID. C<$name> is optional - it is the key to use for
naming node path elements.

    my @nodes = $tree->path_is($path,$name,$startnode);
    my $node = $tree->path_is($path,$name,$startnode);

converts a scalar path to a single node hash (scalar context) or an
array of nodes (list context). C<$name> is optional - it is the key to
use for naming node path elements. C<$startnode> is optional - is is
the node ID to begin the path construction from (defaults to the tree
root).

=head2 Example

This example creates a site map in a tree structure:

    # fetch the system content, ordered by rank and id
    my @content = $db->fetch_all("content", ["sortkey","content_id"]);
    # pass the page data to the Tree class, using content_id and parent 
    # as the index keys
    my $map = new ExSite::Tree("content_id","parent",@data);

That is sufficient to create the tree.  This tree consists of one node for 
each content object, with the nodes nested exactly as they do in site menus 
and site maps.  At each level of the tree, the content is ordered correctly 
according to their sortkeys.

To fetch the top-level content from the site, use:

    my @top = $map->get_topnodes_data();

This retrieves an ordered array of datahashes, representing the top-level
sections/pages of the site.  For each of these items, you can fetch the 
child content beneath them with:

    my @sub = $map->get_child_data($content->{content_id});

...and so on, to any depth.

To get a quick view of the site map, use:

    print $map->dump(0,"name");

=cut

